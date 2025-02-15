-- The main goal of this table is to subtract the charges from the credits and figure out how much is owed, and it what aging bucket it falls in.
-- patnum | BalOver90 | Bal_61_90 | Bal_31_60 | Bal_0_30 | BalTotal | InsWoEst | InsPayEst | PayPlanDue
SELECT * FROM (
    SELECT 
        tSums.patnum, 
        --  All of these case statements are essentially taking the total credit and applying to the charge buckets, beginning with 90+, until the credit is gone. 
        -- So even if it's the procedures that are 90+ days old that haven't gotten paid yet, all of it would be considered 0-30 aging. 
        Round(
            CASE 
                WHEN tSums.totalcredits >= tSums.chargesover90 THEN 0 
                ELSE tSums.chargesover90 - tSums.totalcredits 
            END, 
            3
        ) BalOver90, 
        Round(
            CASE 
                WHEN tSums.totalcredits <= tSums.chargesover90 THEN tSums.charges_61_90 
                WHEN tSums.chargesover90 + tSums.charges_61_90 <= tSums.totalcredits THEN 0 
                ELSE tSums.chargesover90 + tSums.charges_61_90 - tSums.totalcredits 
            END, 
            3
        ) Bal_61_90, 
        Round(
            CASE 
                WHEN tSums.totalcredits < tSums.chargesover90 + tSums.charges_61_90 THEN tSums.charges_31_60 
                WHEN tSums.chargesover90 + tSums.charges_61_90 + tSums.charges_31_60 <= tSums.totalcredits THEN 0 
                ELSE tSums.chargesover90 + tSums.charges_61_90 + tSums.charges_31_60 - tSums.totalcredits 
            END, 
            3
        ) Bal_31_60, 
        Round(
            CASE 
                WHEN tSums.totalcredits < tSums.chargesover90 + tSums.charges_61_90 + tSums.charges_31_60 THEN tSums.charges_0_30 
                WHEN tSums.chargesover90 + tSums.charges_61_90 + tSums.charges_31_60 + tSums.charges_0_30 <= tSums.totalcredits THEN 0 
                ELSE tSums.chargesover90 + tSums.charges_61_90 + tSums.charges_31_60 + tSums.charges_0_30 - tSums.totalcredits 
            END, 
            3
        ) Bal_0_30, 
        Round(tSums.baltotal, 3) BalTotal, 
        Round(tSums.inswoest, 3) InsWoEst, 
        Round(tSums.inspayest, 3) InsPayEst, 
        Round(tSums.payplandue, 3) PayPlanDue 
    FROM 
    -- BEGIN tSums
    -- patnum | ChargesOver90 | Charges_61_90 | Charges_31_60 | Charges_0_30 | TotalCredits | BalTotal | InsWoEst | InsPayEst | PayPlanDue
        (
        SELECT 
        transSums.patnum, 
        Greatest(transSums.chargesover90, 0) ChargesOver90, 
        Greatest(transSums.charges_61_90, 0) Charges_61_90, 
        Greatest(transSums.charges_31_60, 0) Charges_31_60, 
        Greatest(transSums.charges_0_30, 0) Charges_0_30, 
        transSums.totalcredits - Least(transSums.chargesover90, 0) - Least(transSums.charges_61_90, 0) - Least(transSums.charges_31_60, 0) - Least(transSums.charges_0_30, 0) TotalCredits, 
        transSums.baltotal, 
        transSums.inswoest, 
        transSums.inspayest, 
        transSums.payplandue 
        FROM 
        -- BEGIN transSums
        -- patnum | ChargesOver90 | Charges_61_90 | Charges_31_60 | Charges_0_30 | TotalCredits | BalTotal | InsWoEst | InsPayEst | PayPlanDue
        (
            SELECT 
            trans.patnum, 
            Sum(
                CASE WHEN (
                trans.tranamount > 0 
                OR trans.trantype IN (
                    'WriteoffOrig', 'SumByProcAndDate'
                )
                ) 
                AND trans.trandate < '2024-11-12' THEN trans.tranamount ELSE 0 END
            ) ChargesOver90, 
            Sum(
                CASE WHEN (
                trans.tranamount > 0 
                OR trans.trantype IN (
                    'WriteoffOrig', 'SumByProcAndDate'
                )
                ) 
                AND trans.trandate < '2024-12-12' 
                AND trans.trandate >= '2024-11-12' THEN trans.tranamount ELSE 0 END
            ) Charges_61_90, 
            Sum(
                CASE WHEN (
                trans.tranamount > 0 
                OR trans.trantype IN (
                    'WriteoffOrig', 'SumByProcAndDate'
                )
                ) 
                AND trans.trandate < '2025-01-11' 
                AND trans.trandate >= '2024-12-12' THEN trans.tranamount ELSE 0 END
            ) Charges_31_60, 
            Sum(
                CASE WHEN (
                trans.tranamount > 0 
                OR trans.trantype IN (
                    'WriteoffOrig', 'SumByProcAndDate'
                )
                ) 
                AND trans.trandate <= '2025-02-10' 
                AND trans.trandate >= '2025-01-11' THEN trans.tranamount ELSE 0 END
            ) Charges_0_30, 
            - Sum(
                CASE WHEN trans.tranamount < 0 
                AND NOT(
                trans.trantype IN (
                    'WriteoffOrig', 'SumByProcAndDate'
                )
                ) 
                AND trans.trandate <= '2025-02-10' THEN trans.tranamount ELSE 0 END
            ) TotalCredits, 
            Sum( -- Manually enter when not current date
                CASE 
                WHEN trans.tranamount != 0 AND trans.trandate <= '2025-02-10' THEN trans.tranamount 
                ELSE 0 
            END
            ) BalTotal, 
            Sum(trans.inswoest) InsWoEst, 
            Sum(trans.inspayest) InsPayEst, 
            Sum(trans.payplanamount) PayPlanDue 
            FROM 
            -- BEGIN trans
            -- TranType | PriKey | patnum | TranDate | TranAmount | PayPlanAmount | InsWoEst | InsPayEst
            (
                SELECT 
                (
                    CASE WHEN tranbyproc.agedprocnum = 0 THEN tranbyproc.trantype ELSE 'SumByProcAndDate' END
                ) TranType, 
                0 PriKey, 
                tranbyproc.patnum, 
                (
                    CASE WHEN tranbyproc.agedprocnum != 0 
                    AND Sum(tranbyproc.tranamount) < 0 THEN tranbyproc.agedprocdate ELSE tranbyproc.trandate END
                ) TranDate, 
                Sum(tranbyproc.tranamount) TranAmount, 
                Sum(tranbyproc.payplanamount) PayPlanAmount, 
                Sum(tranbyproc.inswoest) InsWoEst, 
                Sum(tranbyproc.inspayest) InsPayEst 
                FROM 
                -- BEGIN tranbyproc
                -- TranType | PriKey | patnum | TranDate | TranAmount | PayPlanAmount | InsWoEst | InsPayEst | AgedProcNum | AgedProcDate
                (
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
                    SELECT 
                    'Claimproc' TranType, 
                    cp.claimprocnum PriKey, 
                    cp.patnum, 
                    cp.datecp TranDate, 
                    ( 
                        CASE WHEN cp.status != 0 THEN ( -- if the claim status is not "not received" then...
                        CASE WHEN cp.payplannum = 0 THEN - cp.inspayamt ELSE 0 END -- if the claim is not tied to a payplan then = -what insurance paid
                        ) - cp.writeoff ELSE 0 END -- -the amount not covered by insurance
                    ) TranAmount, 
                    0 PayPlanAmount, 
                    ( -- this will equate to 0 if the claim has been received, otherwise it's the writeoff (the writeoff is auto populated with the estimate before the claim is received)
                        CASE WHEN cp.procdate <= '2025-02-10' AND (cp.status = 0 OR (cp.status = 1 AND cp.datecp > '2025-02-10')) THEN cp.writeoff ELSE 0 END -- Manually enter when not current date
                    ) InsWoEst, 
                    ( -- this will equate to 0 if the claim has been received, otherwise it's the insurance pay estimate
                        CASE WHEN cp.procdate <= '2025-02-10' AND (cp.status = 0 OR (cp.status = 1 AND cp.datecp > '2025-02-10')) THEN cp.writeoff ELSE 0 END -- Manually enter when not current date
                    ) InsPayEst, 
                    0 AgedProcNum, 
                    '0001-01-01' AgedProcDate 
                    FROM 
                    claimproc cp 
                    LEFT JOIN procedurelog p ON cp.procnum = p.procnum -- this is just here to filter for complete procedures
                    WHERE -- all claimprocs that are not received, received, supplemental, claimcap, capcomplete AND payments by total (no procnum) OR the procedure is complete
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
                    SELECT 
                    'Adj' TranType, 
                    a.adjnum PriKey, 
                    a.patnum, 
                    a.adjdate TranDate, 
                    a.adjamt TranAmount, 
                    0 PayPlanAmount, 
                    0 InsWoEst, 
                    0 InsPayEst, 
                    a.procnum AgedProcNum, 
                    a.procdate AgedProcDate 
                    FROM 
                    adjustment a 
                    WHERE 
                    a.adjamt != 0 
                    UNION ALL 
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
                    ps.splitamt != 0 AND and ps.datepay <= '2025-02-10' -- Manually enter when not current date
                    UNION ALL 
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
                -- END tranbyproc
                GROUP BY 
                tranbyproc.patnum, 
                tranbyproc.agedprocnum, 
                tranbyproc.trandate, 
                (
                    CASE WHEN tranbyproc.agedprocnum = 0 THEN tranbyproc.trantype ELSE 'SumByProcAndDate' END
                ), 
                (
                    CASE WHEN tranbyproc.agedprocnum = 0 
                    AND tranbyproc.tranamount >= 0 THEN 'credit' WHEN tranbyproc.agedprocnum = 0 
                    AND tranbyproc.tranamount < 0 THEN 'charge' ELSE 'SumByProcAndDate' END
                )
            ) trans 
            -- END trans
            GROUP BY 
            trans.patnum
        ) transSums
        -- END transSums
        ) tSums
    -- END tSums
) guarAging