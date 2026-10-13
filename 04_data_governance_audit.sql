-- =============================================================================
-- Analysis 4: DATA GOVERNANCE & UNMAPPED TAIL SPEND AUDIT
-- Objective: Audit classification coverage, unmapped exposure, and supplier tail spend
-- =============================================================================
WITH Classification_Audit AS (
    -- STEP 1: Evaluate mapped vs unmapped records
    SELECT CASE
            WHEN "Carbonsaver_Category" IS NULL
            OR "Carbonsaver_Category" IN ('Unmapped', 'Not Classified', '') THEN 'Unclassified / Unmapped Spend'
            ELSE 'Fully Mapped Spend'
        END AS mapping_status,
        COUNT(*) AS transaction_count,
        SUM("Amount") AS total_spend_gbp,
        SUM("Carbon_Emissions_tCO2e") AS total_tco2e
    FROM trafford_spend_emissions_3yr
    GROUP BY CASE
            WHEN "Carbonsaver_Category" IS NULL
            OR "Carbonsaver_Category" IN ('Unmapped', 'Not Classified', '') THEN 'Unclassified / Unmapped Spend'
            ELSE 'Fully Mapped Spend'
        END
),
Overall_Totals AS (
    -- STEP 2: Calculate grand totals for percentage coverage
    SELECT SUM(transaction_count) AS grand_total_transactions,
        SUM(total_spend_gbp) AS grand_total_spend,
        SUM(total_tco2e) AS grand_total_tco2e
    FROM Classification_Audit
) -- STEP 3: Produce Executive Governance Metrics
SELECT c.mapping_status,
    c.transaction_count,
    ROUND(
        (
            c.transaction_count::numeric / o.grand_total_transactions * 100
        ),
        2
    ) AS transaction_share_pct,
    ROUND(c.total_spend_gbp::numeric, 2) AS total_spend_gbp,
    ROUND(
        (c.total_spend_gbp / o.grand_total_spend * 100)::numeric,
        2
    ) AS spend_share_pct,
    ROUND(c.total_tco2e::numeric, 2) AS total_tco2e,
    ROUND(
        (c.total_tco2e / o.grand_total_tco2e * 100)::numeric,
        2
    ) AS carbon_share_pct,
    CASE
        WHEN c.mapping_status = 'Unclassified / Unmapped Spend' THEN 'High Audit Risk (Missing EEIO Factors)'
        ELSE 'Low Audit Risk (Verified Scope 3 Mapping)'
    END AS governance_risk_rating
FROM Classification_Audit c
    CROSS JOIN Overall_Totals o;