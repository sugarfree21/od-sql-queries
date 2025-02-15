SELECT 
  patient.fname, 
  patient.lname, 
  patient.patnum, 
  guarAging.Bal_0_30, 
  guarAging.Bal_31_60, 
  guarAging.Bal_61_90, 
  guarAging.BalOver90, 
  guarAging.BalTotal 
FROM 
  (
    SELECT 
      tSums.PatNum, 
      ROUND(
        CASE WHEN tSums.TotalCredits >= tSums.ChargesOver90 THEN 0 ELSE tSums.ChargesOver90 - tSums.TotalCredits END, 
        3
      ) BalOver90, 
      ROUND(
        CASE WHEN tSums.TotalCredits <= tSums.ChargesOver90 THEN tSums.Charges_61_90 WHEN tSums.ChargesOver90 + tSums.Charges_61_90 <= tSums.TotalCredits THEN 0 ELSE tSums.ChargesOver90 + tSums.Charges_61_90 - tSums.TotalCredits END, 
        3
      ) Bal_61_90, 
      ROUND(
        CASE WHEN tSums.TotalCredits < tSums.ChargesOver90 + tSums.Charges_61_90 THEN tSums.Charges_31_60 WHEN tSums.ChargesOver90 + tSums.Charges_61_90 + tSums.Charges_31_60 <= tSums.TotalCredits THEN 0 ELSE tSums.ChargesOver90 + tSums.Charges_61_90 + tSums.Charges_31_60 - tSums.TotalCredits END, 
        3
      ) Bal_31_60, 
      ROUND(
        CASE WHEN tSums.TotalCredits < tSums.ChargesOver90 + tSums.Charges_61_90 + tSums.Charges_31_60 THEN tSums.Charges_0_30 WHEN tSums.ChargesOver90 + tSums.Charges_61_90 + tSums.Charges_31_60 + tSums.Charges_0_30 <= tSums.TotalCredits THEN 0 ELSE tSums.ChargesOver90 + tSums.Charges_61_90 + tSums.Charges_31_60 + tSums.Charges_0_30 - tSums.TotalCredits END, 
        3
      ) Bal_0_30, 
      ROUND(
        tSums.TotalCharges - tSums.TotalCredits, 
        3
      ) BalTotal 
    FROM 
      (
        SELECT 
          p.PatNum, 
          SUM(
            CASE WHEN trans.TranAmount > 0 
            AND trans.TranDate >= '2025-02-01' - INTERVAL 30 DAY THEN trans.TranAmount ELSE 0 END
          ) Charges_0_30, 
          SUM(
            CASE WHEN trans.TranAmount > 0 
            AND trans.TranDate BETWEEN '2025-02-01' - INTERVAL 60 DAY 
            AND '2025-02-01' - INTERVAL 31 DAY THEN trans.TranAmount ELSE 0 END
          ) Charges_31_60, 
          SUM(
            CASE WHEN trans.TranAmount > 0 
            AND trans.TranDate BETWEEN '2025-02-01' - INTERVAL 90 DAY 
            AND '2025-02-01' - INTERVAL 61 DAY THEN trans.TranAmount ELSE 0 END
          ) Charges_61_90, 
          SUM(
            CASE WHEN trans.TranAmount > 0 
            AND trans.TranDate < '2025-02-01' - INTERVAL 90 DAY THEN trans.TranAmount ELSE 0 END
          ) ChargesOver90, 
          SUM(
            CASE WHEN trans.TranAmount > 0 THEN trans.TranAmount ELSE 0 END
          ) AS TotalCharges, 
          - SUM(
            CASE WHEN trans.TranAmount < 0 
            AND trans.TranDate >= '2025-02-01' - INTERVAL 30 DAY THEN trans.TranAmount ELSE 0 END
          ) Credits_0_30, 
          - SUM(
            CASE WHEN trans.TranAmount < 0 
            AND trans.TranDate BETWEEN '2025-02-01' - INTERVAL 60 DAY 
            AND '2025-02-01' - INTERVAL 31 DAY THEN trans.TranAmount ELSE 0 END
          ) Credits_31_60, 
          - SUM(
            CASE WHEN trans.TranAmount < 0 
            AND trans.TranDate BETWEEN '2025-02-01' - INTERVAL 90 DAY 
            AND '2025-02-01' - INTERVAL 61 DAY THEN trans.TranAmount ELSE 0 END
          ) Credits_61_90, 
          - SUM(
            CASE WHEN trans.TranAmount < 0 
            AND trans.TranDate < '2025-02-01' - INTERVAL 90 DAY THEN trans.TranAmount ELSE 0 END
          ) CreditsOver90, 
          - SUM(
            CASE WHEN trans.TranAmount < 0 THEN trans.TranAmount ELSE 0 END
          ) AS TotalCredits, 
          SUM(
            CASE WHEN trans.TranAmount != 0 THEN trans.TranAmount ELSE 0 END
          ) BalTotal 
        FROM 
          (
            SELECT 
              'Proc' TranType, 
              pl.PatNum, 
              pl.ProcDate TranDate, 
              pl.ProcFee *(pl.UnitQty + pl.BaseUnits) TranAmount 
            FROM 
              procedurelog pl 
            WHERE 
              pl.ProcStatus = 2 
              AND pl.ProcFee != 0 
              AND pl.ProcDate <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'InsPay' TranType, 
              cp.PatNum, 
              cp.DateCP TranDate, 
              - cp.InsPayAmt TranAmount 
            FROM 
              claimproc cp 
            WHERE 
              cp.Status IN (1, 4, 5, 7) 
              AND cp.InsPayAmt != 0 
              AND cp.PayPlanNum = 0 
              AND cp.DateCP <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'Writeoff' TranType, 
              cp.PatNum, 
              cp.DateCP TranDate, 
              - cp.Writeoff TranAmount 
            FROM 
              claimproc cp 
            WHERE 
              cp.Status IN (1, 4, 5, 7) 
              AND cp.WriteOff != 0 
              AND cp.DateCP <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'WriteoffEst' TranType, 
              cp.PatNum, 
              cp.DateCP TranDate, 
              COALESCE(
                IF(
                  claimsnapshot.Writeoff = -1, 0,- claimsnapshot.Writeoff
                ), 
                0
              ) TranAmount 
            FROM 
              claimproc cp 
              LEFT JOIN claimsnapshot ON cp.ClaimProcNum = claimsnapshot.ClaimProcNum 
            WHERE 
              cp.Status = 0 
              AND cp.DateCP <= '2025-02-01' 
            GROUP BY 
              cp.ClaimProcNum 
            HAVING 
              TranAmount != 0 
            UNION ALL 
            SELECT 
              'Adj' TranType, 
              adj.PatNum, 
              adj.AdjDate TranDate, 
              adj.AdjAmt TranAmount 
            FROM 
              adjustment adj 
            WHERE 
              adj.AdjAmt != 0 
              AND adj.AdjDate <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'PPComplete' TranType, 
              (
                CASE WHEN pp.PlanNum > 0 THEN ppc.PatNum ELSE ppc.Guarantor END
              ) PatNum, 
              ppc.ChargeDate TranDate, 
              (
                CASE WHEN ppc.ChargeType != 0 THEN - ppc.Principal WHEN pp.PlanNum = 0 THEN ppc.Principal + ppc.Interest ELSE 0 END
              ) TranAmount 
            FROM 
              payplancharge ppc 
              LEFT JOIN payplan pp ON pp.PayPlanNum = ppc.PayPlanNum 
            WHERE 
              ppc.ChargeDate <= '2025-02-01' 
              AND ppc.ChargeType IN (0, 1) 
            UNION ALL 
            SELECT 
              'PayPlanLink' TranType, 
              prodlink.PatNum PatNum, 
              DATE(payplanlink.SecDateTEntry) TranDate, 
              (
                CASE WHEN payplanlink.AmountOverride = 0 THEN - prodlink.Fee ELSE - payplanlink.AmountOverride END
              ) TranAmount 
            FROM 
              payplanlink 
              LEFT JOIN (
                SELECT 
                  procedurelog.PatNum, 
                  (
                    procedurelog.ProcFee *(
                      procedurelog.UnitQty + procedurelog.BaseUnits
                    ) + COALESCE(procAdj.AdjAmt, 0)+ COALESCE(procClaimProc.InsPay, 0) + COALESCE(procClaimProc.WriteOff, 0) + COALESCE(procSplit.SplitAmt, 0)
                  ) Fee, 
                  payplanlink.PayPlanLinkNum LinkNum, 
                  procedurelog.ProcNum, 
                  procedurelog.ProcDate AgeDate 
                FROM 
                  payplanlink 
                  INNER JOIN payplan ON payplanlink.PayPlanNum = payplan.PayPlanNum 
                  INNER JOIN procedurelog ON procedurelog.ProcNum = payplanlink.FKey 
                  AND payplanlink.LinkType = 2 
                  AND !(
                    payplan.dynamicPayPlanTPOption = 1 
                    AND procedurelog.ProcStatus != 2
                  ) 
                  LEFT JOIN (
                    SELECT 
                      SUM(adjustment.AdjAmt) AdjAmt, 
                      adjustment.ProcNum, 
                      adjustment.PatNum, 
                      adjustment.ProvNum, 
                      adjustment.ClinicNum 
                    FROM 
                      adjustment 
                    GROUP BY 
                      adjustment.ProcNum, 
                      adjustment.PatNum, 
                      adjustment.ProvNum, 
                      adjustment.ClinicNum
                  ) procAdj ON procAdj.ProcNum = procedurelog.ProcNum 
                  AND procAdj.PatNum = procedurelog.PatNum 
                  AND procAdj.ProvNum = procedurelog.ProvNum 
                  AND procAdj.ClinicNum = procedurelog.ClinicNum 
                  LEFT JOIN (
                    SELECT 
                      SUM(
                        COALESCE(
                          (
                            CASE WHEN claimproc.Status IN (1, 4, 7) THEN claimproc.InsPayAmt WHEN claimproc.InsEstTotalOverride !=-1 THEN claimproc.InsEstTotalOverride ELSE claimproc.InsPayEst END
                          ), 
                          0
                        )*-1
                      ) InsPay, 
                      SUM(
                        COALESCE(
                          (
                            CASE WHEN claimproc.Status IN (1, 4, 7) THEN claimproc.WriteOff WHEN claimproc.WriteOffEstOverride !=-1 THEN claimproc.WriteOffEstOverride WHEN claimproc.WriteOffEst !=-1 THEN claimproc.WriteOffEst ELSE 0 END
                          ), 
                          0
                        )*-1
                      ) WriteOff, 
                      claimproc.ProcNum 
                    FROM 
                      claimproc 
                    WHERE 
                      claimproc.Status != 2 
                    GROUP BY 
                      claimproc.ProcNum
                  ) procClaimProc ON procClaimProc.ProcNum = procedurelog.ProcNum 
                  LEFT JOIN (
                    SELECT 
                      SUM(paysplit.SplitAmt)*-1 SplitAmt, 
                      paysplit.ProcNum 
                    FROM 
                      paysplit 
                    WHERE 
                      paysplit.PayPlanNum = 0 
                    GROUP BY 
                      paysplit.ProcNum
                  ) procSplit ON procSplit.ProcNum = procedurelog.ProcNum 
                UNION ALL 
                SELECT 
                  adjustment.PatNum, 
                  adjustment.AdjAmt + COALESCE(adjSplit.SplitAmt, 0) Fee, 
                  payplanlink.PayPlanLinkNum LinkNum, 
                  0 ProcNum, 
                  DATE('0001-01-01') AgeDate 
                FROM 
                  payplanlink 
                  INNER JOIN adjustment ON adjustment.AdjNum = payplanlink.FKey 
                  AND payplanlink.LinkType = 1 
                  LEFT JOIN (
                    SELECT 
                      SUM(
                        COALESCE(paysplit.SplitAmt, 0)
                      )*-1 SplitAmt, 
                      paysplit.AdjNum 
                    FROM 
                      paysplit 
                    WHERE 
                      paysplit.PayPlanNum = 0 
                    GROUP BY 
                      paysplit.AdjNum
                  ) adjSplit ON adjSplit.AdjNum = adjustment.AdjNum
              ) prodlink ON prodlink.LinkNum = payplanlink.PayPlanLinkNum 
            WHERE 
              prodlink.AgeDate <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'PayPlanLink' TranType, 
              p.PatNum, 
              p.ProcDate, 
              COALESCE(p.Discount + p.DiscountPlanAmt) 
            FROM 
              procedurelog p 
              INNER JOIN payplanlink ppl ON p.ProcNum = ppl.FKey 
              AND ppl.FKey = p.ProcNum 
              AND ppl.LinkType = 2 
              INNER JOIN payplan pp ON ppl.PayPlanNum = pp.PayPlanNum 
            WHERE 
              pp.IsDynamic = 1 
              AND pp.DynamicPayPlanTPOption = 2 
              AND (
                p.Discount != 0 
                OR p.DiscountPlanAmt != 0
              ) 
              AND p.ProcStatus = 1 
              AND p.ProcDate <= '2025-02-01' 
            UNION ALL 
            SELECT 
              'PatPay' TranType, 
              ps.PatNum, 
              ps.DatePay TranDate, 
              - ps.SplitAmt TranAmount 
            FROM 
              paysplit ps 
            WHERE 
              ps.SplitAmt != 0 
              AND ps.DatePay <= '2025-02-01' 
              AND ps.UnearnedType NOT IN (301, 325) 
            UNION ALL 
            SELECT 
              'InsEst' TranType, 
              cp.PatNum, 
              cp.DateCP TranDate, 
              - cp.InsPayEst TranAmount 
            FROM 
              claimproc cp 
            WHERE 
              cp.Status = 0 
              AND cp.InsPayEst != 0 
              AND cp.DateCP <= '2025-02-01'
          ) trans 
          INNER JOIN patient p ON p.PatNum = trans.PatNum 
        GROUP BY 
          p.PatNum
      ) tSums
  ) guarAging 
  INNER JOIN patient ON patient.PatNum = guarAging.PatNum 
WHERE 
  TRUE 
  AND (
    guarAging.BalOver90 != 0 
    OR guarAging.Bal_61_90 != 0 
    OR guarAging.Bal_31_60 != 0 
    OR guarAging.Bal_0_30 != 0
  ) 
  AND guarAging.BalTotal > 0 
ORDER BY 
  patient.LName, 
  patient.FName
