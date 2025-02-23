-- Positive number is what they owe us, negative number is what they have paid us
SET @query_date = '2024-12-31'; -- The report will include this date
SET @ten_days_forward = date_add(@query_date, INTERVAL 10 DAY);

SELECT * FROM (
    SELECT
        TranType,
        ProcNum,
        patnum,
        TranDate,
        ProcDate,
        SUM(TranAmount),
        SUM(PayPlanAmount),
        SUM(InsTotEst),
        SUM(InsPayEst),
        SUM(InsWoEst),
        (CASE WHEN TranAmount > 0 THEN "Charge" ELSE "Credit" END) CC
    FROM (
        -- Complete procedures, not filtered by whether or not they've been paid. 
        SELECT 
            'Proc' TranType, 
            pl.procnum ProcNum, 
            pl.patnum, 
            pl.procdate TranDate, 
            pl.procdate ProcDate, 
            pl.procfee * (pl.unitqty + pl.baseunits) TranAmount, 
            0 PayPlanAmount, 
            0 InsTotEst,
            0 InsWoEst, 
            0 InsPayEst
        FROM 
            procedurelog pl 
        WHERE 
            pl.procstatus = 2 -- This is an important assumption, we're only grabbing procedures of status 2, or that are complete
            AND pl.procfee != 0 
            AND pl.procdate <= @query_date
        UNION ALL 
        -- All procedures that have been billed out to insurance, either showing the total cost of the procedure (actual pay + writeoff) or estimates for both values. This is true even if the claim has been denied
        SELECT 
            'Claimproc' TranType, 
            cp.procnum ProcNum, 
            cp.patnum, 
            cp.datecp TranDate, -- this is the date of the payment once it's been attached. I think that it's the date the claim was sent before that
            cp.procdate ProcDate, -- this is the date that the procedure was completed
            ( 
                CASE WHEN cp.status != 0 OR cp.datecp > @query_date THEN ( -- if the claim hasn't been received or it was received after the query date then 0. If the claim was received before the query date, and there's no payplan, then -inspayamt-writeoff. If the claim was received before the query date and there is a payplan, then 0
                    CASE WHEN cp.payplannum = 0 THEN - cp.inspayamt ELSE 0 END
                ) - cp.writeoff ELSE 0 END
            ) TranAmount, 
            0 PayPlanAmount, 
            ( -- this will equate to 0 if the claim has been received, otherwise it's the whole amount insurance was billed
            CASE WHEN cp.procdate <= @query_date AND (cp.status = 0 OR (cp.status = 1 AND cp.datecp > @query_date)) THEN cp.inspayest + cp.writeoff ELSE 0 END
            ) InsTotEst,
            ( -- this will equate to 0 if the claim has been received, otherwise it's the writeoff (the writeoff is auto populated with the estimate before the claim is received)
            CASE WHEN cp.procdate <= @query_date AND (cp.status = 0 OR (cp.status = 1 AND cp.datecp > @query_date)) THEN cp.writeoff ELSE 0 END
            ) InsWoEst, 
            ( -- this will equate to 0 if the claim has been received, otherwise it's the insurance pay estimate
            CASE WHEN cp.procdate <= @query_date AND (cp.status = 0 OR (cp.status = 1 AND cp.datecp > @query_date)) THEN cp.inspayest ELSE 0 END
            ) InsPayEst
        FROM 
            claimproc cp 
            LEFT JOIN procedurelog p ON cp.procnum = p.procnum -- this is just here to filter for complete procedures
        WHERE -- all claimprocs that are not received, received, supplemental, claimcap, capcomplete AND payments by total (no procnum) OR the procedure is complete. This is important, because it's not including estimates.
            cp.status IN (0, 1, 4, 5, 7) 
            AND ( cp.procnum = 0 OR p.procstatus = 2) 
            AND cp.procdate <= @query_date
        HAVING 
            tranamount != 0 
            OR inswoest != 0 
            OR inspayest != 0 
        UNION ALL 
        -- All adjustments, pretty standard. These are negative generally speaking, which means we're lowering the amount that we're charging the patient
        SELECT 
            'Adj' TranType, 
            a.procnum ProcNum, 
            a.patnum, 
            a.procdate TranDate, 
            a.procdate ProcDate,
            a.adjamt TranAmount, 
            0 PayPlanAmount, 
            0 InsTotEst,
            0 InsWoEst, 
            0 InsPayEst
        FROM 
            adjustment a 
        WHERE 
            a.adjamt != 0
            AND a.procdate <= @query_date
        UNION ALL 
        -- This is here to offset the full charge of the patient plan on the ledger
        SELECT 
            'PPOffset' TranType, 
            pp.payplannum PriKey, 
            pp.patnum, 
            pp.payplandate TranDate, 
            pp.payplandate ProcDate,
            - pp.completedamt TranAmount, 
            0 PayPlanAmount, 
            0 InsTotEst,
            0 InsWoEst, 
            0 InsPayEst
        FROM 
            payplan pp 
        WHERE 
            pp.completedamt != 0
            AND pp.payplandate <= @query_date
        UNION ALL 
        -- Total amount we will ever bill for all open patient plans (existing payments will be subtracted). After offsetting payments, this will be a separate field that is added onto the patient pay total
        SELECT 
            'PPTotal' TranType, 
            pp.payplannum PriKey, 
            pp.patnum, 
            pp.payplandate TranDate, 
            pp.payplandate ProcDate,
            0 TranAmount,
            pp.completedamt PayPlanAmount, 
            0 InsTotEst,
            0 InsWoEst, 
            0 InsPayEst 
        FROM 
            payplan pp 
        WHERE 
            pp.completedamt != 0 AND isclosed = 0 -- filter by real payplans that are not closed (meaning we can still expect some money)
            AND pp.payplandate <= @query_date
        UNION ALL 
        -- each payment after it's already split. The payment cost is either listed as tranamount or payplanamount based on if it's a payplan
        SELECT 
            'PatPay' TranType, 
            ps.splitnum PriKey, 
            ps.patnum, 
            ps.datepay TranDate, 
            ps.procdate ProcDate,
            ( -- the negative paysplit amount is put into TranAmount if there is no payplan
            CASE WHEN ps.payplannum = 0 THEN - ps.splitamt ELSE 0 END
            ) TranAmount, 
            ( -- the negative paysplit amount is put into PayPlanAmount if there is an open payplan
            CASE WHEN ps.payplannum != 0 THEN - ps.splitamt ELSE 0 END
            ) PayPlanAmount, 
            0 InsTotEst,
            0 InsWoEst, 
            0 InsPayEst
        FROM 
            paysplit ps 
            LEFT JOIN payplan pp ON ps.payplannum = pp.payplannum -- Just here to filter for open payplans
        WHERE 
            ps.splitamt != 0 AND ps.datepay <= @query_date AND (ps.payplannum = 0 OR (ps.payplannum != 0 AND pp.isclosed = 0))
            AND ps.datepay <= @query_date
    ) tranbyproc
    GROUP BY
        patnum,
        TranDate,
        ProcDate,
        TranType,
        (CASE WHEN TranAmount > 0 THEN "Charge" ELSE "Credit" END)
) daysummaries