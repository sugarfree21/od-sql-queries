-- The main goal of this table seems to be compiling a number of other tables so that you have every transaction that happens within OD sorted by type
-- TranType | PriKey | patnum | TranDate | TranAmount | PayPlanAmount | InsWoEst | InsPayEst | AgedProcNum | AgedProcDate
-- Positive number is what they owe us, negative number is what they have paid us
SELECT * FROM (
    -- Complete procedures, not filtered by whether or not they've been paid. 
    SELECT 
        'Proc' TranType, 
        pl.procnum PriKey, 
        pl.patnum, 
        pl.procdate TranDate, 
        pl.procfee * (pl.unitqty + pl.baseunits) TranAmount, 
        0 PayPlanAmount, 
        0 InsWoEst, 
        0 InsPayEst, 
        0 AgedProcNum, 
        '0001-01-01' AgedProcDate 
    FROM 
        procedurelog pl 
    WHERE 
        pl.procstatus = 2 -- This is an important assumption, we're only grabbing procedures of status 2, or that are complete
        AND pl.procfee != 0 
    UNION ALL 
    -- All procedures that have been billed out to insurance, either showing the total cost of the procedure (actual pay + writeoff) or estimates for both values. This is true even if the claim has been denied
    SELECT 
        'Claimproc' TranType, 
        cp.claimprocnum PriKey, 
        cp.patnum, 
        cp.datecp TranDate, -- this is the date of the payment once it's been attached. I think that it's the date the claim was sent before that
        ( 
        CASE WHEN cp.status != 0 THEN ( -- if the claim hasn't been received then 0. If the claim has been received, and there's no payplan, then -inspayamt-writeoff. If the claim has been received and there is a payplan, then 0
            CASE WHEN cp.payplannum = 0 THEN - cp.inspayamt ELSE 0 END
        ) - cp.writeoff ELSE 0 END
        ) TranAmount, 
        0 PayPlanAmount, 
        ( -- this will equate to 0 if the claim has been received, otherwise it's the writeoff (the writeoff is auto populated with the estimate before the claim is received)
        CASE WHEN cp.status = 0 THEN cp.writeoff ELSE 0 END
        ) InsWoEst, 
        ( -- this will equate to 0 if the claim has been received, otherwise it's the insurance pay estimate
        CASE WHEN cp.status = 0 THEN cp.inspayest ELSE 0 END
        ) InsPayEst, 
        0 AgedProcNum, 
        '0001-01-01' AgedProcDate 
    FROM 
        claimproc cp 
        LEFT JOIN procedurelog p ON cp.procnum = p.procnum -- this is just here to filter for complete procedures
    WHERE -- all claimprocs that are not received, received, supplemental, claimcap, capcomplete AND payments by total (no procnum) OR the procedure is complete. This is important, because it's not including estimates.
        cp.status IN (0, 1, 4, 5, 7) 
        AND (
        cp.procnum = 0 
        OR p.procstatus = 2
        ) 
    HAVING 
        tranamount != 0 
        OR inswoest != 0 
        OR inspayest != 0 
    UNION ALL 
    -- All adjustments, pretty standard. These are negative generally speaking, which means we're lowering the amount that we're charging the patient
    SELECT 
        'Adj' TranType, 
        a.adjnum PriKey, 
        a.patnum, 
        a.adjdate TranDate, 
        a.adjamt TranAmount, 
        0 PayPlanAmount, 
        0 InsWoEst, 
        0 InsPayEst, 
        a.procnum AgedProcNum, -- This is the only transaction type that uses agedprocnum, and it's only when a procedure is attached to the adjustment
        a.procdate AgedProcDate -- This is the only type that also puts anything serious into agedprocdate
    FROM 
        adjustment a 
    WHERE 
        a.adjamt != 0 
    UNION ALL 
    -- each payment after it's already split. The payment cost is either listed as tranamount or payplanamount based on if it's a payplan
    SELECT 
        'PatPay' TranType, 
        ps.splitnum PriKey, 
        ps.patnum, 
        ps.datepay TranDate, 
        ( -- the negative paysplit amount is put into TranAmount if there is no payplan
        CASE WHEN ps.payplannum = 0 THEN - ps.splitamt ELSE 0 END
        ) TranAmount, 
        ( -- the negative paysplit amount is put into PayPlanAmount if there is a payplan
        CASE WHEN ps.payplannum != 0 THEN - ps.splitamt ELSE 0 END
        ) PayPlanAmount, 
        0 InsWoEst, 
        0 InsPayEst, 
        0 AgedProcNum, 
        '0001-01-01' AgedProcDate 
    FROM 
        paysplit ps 
    WHERE 
        ps.splitamt != 0 
    UNION ALL 
    -- All of the payplan charges. All of these ought to be paid, but that's not always the case
    SELECT 
        'PPCharge' TranType, 
        ppc.payplanchargenum PriKey, 
        ppc.guarantor PatNum, 
        ppc.chargedate TranDate, 
        0 TranAmount, 
        ppc.principal + ppc.interest PayPlanAmount, 
        0 InsWoEst, 
        0 InsPayEst, 
        0 AgedProcNum, 
        '0001-01-01' AgedProcDate 
    FROM 
        payplancharge ppc 
        INNER JOIN payplan pp ON ppc.payplannum = pp.payplannum 
    WHERE 
        ppc.chargedate <= '2025-02-20' 
        AND ppc.chargetype = 0 
        AND ppc.principal + ppc.interest != 0 
        AND pp.plannum = 0 -- must be non-standard payment plan
    UNION ALL 
    -- This one is weird. The transaction amount is equal to all of the procedures tied to the plan that have been completed. It essentially is there to offset the charges for procedures that are going to be completed via payment plan. 
    SELECT 
        'PPComplete' TranType, 
        pp.payplannum PriKey, 
        pp.patnum, 
        pp.payplandate TranDate, 
        - pp.completedamt TranAmount, 
        0 PayPlanAmount, 
        0 InsWoEst, 
        0 InsPayEst, 
        0 AgedProcNum, 
        '0001-01-01' AgedProcDate 
    FROM 
        payplan pp 
    WHERE 
        pp.completedamt != 0
) tranbyproc