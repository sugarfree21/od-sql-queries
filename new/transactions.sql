SET @query_date = '2026-03-01'; -- Exclusive
SET @clinic_filter = '1';

SELECT
    concat(p.fname, ' ', p.lname) as pat_name,
    p.clinicnum as pat_clinic,
    t.*
FROM (
    -- Complete procedures, not filtered by whether or not they've been paid.
    SELECT 
        'Proc' TranType, 
        pl.procnum PriKey, 
        pl.patnum, 
        pl.clinicnum,
        pl.procdate TranDate, 
        pl.procfee * (pl.unitqty + pl.baseunits) TranAmount, 
        0 WoAmount
    FROM 
        procedurelog pl 
    WHERE 
        pl.procstatus = 2 -- This is an important assumption, we're only grabbing procedures of status 2, or that are complete
        AND pl.procfee != 0 
        AND pl.procdate < @query_date
        -- AND pl.clinicnum = @clinic_filter
    UNION ALL 
    -- All procedures that have been billed out to insurance, either showing the total cost of the procedure (actual pay + writeoff) or estimates for both values. This is true even if the claim has been denied
    SELECT 
        'InsPay' TranType, 
        cp.claimprocnum PriKey, 
        cp.patnum, 
        cp.clinicnum,
        cp.datecp TranDate, -- this is the date of the payment once it's been attached. I think that it's the date the claim was sent before that
        (
            CASE WHEN cp.status != 0 AND cp.datecp < @query_date THEN ( -- if the claim hasn't been received or it was received outside the query dates then 0. If the claim was received inside the query dates, and there's no payplan, then -inspayamt. If the claim was received inside the query dates and there is a payplan, then 0
                CASE WHEN cp.payplannum = 0 THEN - cp.inspayamt ELSE 0 END
            ) ELSE 0 END
        ) TranAmount, 
        ( 
            CASE WHEN cp.status != 0 AND cp.datecp < @query_date THEN ( -- if the claim hasn't been received or it was received outside the query dates then 0. If the claim was received inside the query dates, and there's no payplan, then -writeoff. If the claim was received inside the query dates and there is a payplan, then 0
                CASE WHEN cp.payplannum = 0 THEN - cp.writeoff ELSE 0 END
            ) ELSE 0 END
        ) WoAmount
    FROM 
        claimproc cp 
        LEFT JOIN procedurelog p ON cp.procnum = p.procnum -- this is just here to filter for complete procedures
    WHERE -- all claimprocs that are not received, received, supplemental, claimcap, capcomplete AND payments by total (no procnum) OR the procedure is complete. This is important, because it's not including estimates.
        cp.status IN (0, 1, 4, 5, 7) 
        AND ( cp.procnum = 0 OR p.procstatus = 2) 
        AND cp.procdate < @query_date -- only grabbing claims for procedures that took place before the queried time period
        -- AND cp.clinicnum = @clinic_filter
    HAVING 
        tranamount != 0 
        OR woamount != 0
    UNION ALL 
    -- All adjustments, pretty standard. These are negative generally speaking, which means we're lowering the amount that we're charging the patient
    SELECT 
        'Adj' TranType, 
        a.adjnum PriKey, 
        a.patnum, 
        a.clinicnum,
        a.procdate TranDate, 
        a.adjamt TranAmount, 
        0 WoAmount
    FROM 
        adjustment a 
    WHERE 
        a.adjamt != 0
        AND a.procdate < @query_date
        -- AND a.clinicnum = @clinic_filter
    UNION ALL 
    -- each payment after it's already split
    SELECT 
        'PatPay' TranType, 
        ps.splitnum PriKey, 
        ps.patnum, 
        ps.clinicnum,
        ps.datepay TranDate, 
        - ps.splitamt TranAmount,
        0 WoAmount
    FROM 
        paysplit ps 
        LEFT JOIN payment p ON ps.paynum = p.paynum
    WHERE 
        ps.splitamt != 0 AND ps.datepay < @query_date
        -- AND ps.clinicnum = @clinic_filter
) t
left join patient p on t.patnum = p.patnum