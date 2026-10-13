-- =============================================================================
-- ANALYSIS 1: SCOPE 3 PARETO ANALYSIS (SUPPLIER CONCENTRATION)
-- Objective: Isolate the top suppliers accounting for 80% of total tCO2e
-- =============================================================================
WITH Supplier_Totals AS (
    -- STEP 1: Aggregate spend and carbon per supplier
    SELECT "BeneficiaryName" AS "Supplier_Name",
        COUNT(*) AS transaction_count,
        ROUND(SUM("Amount")::numeric, 2) AS total_spend_gbp,
        ROUND(SUM("Carbon_Emissions_tCO2e")::numeric, 2) AS total_tco2e
    FROM trafford_spend_emissions_3yr
    WHERE "BeneficiaryName" IS NOT NULL
    GROUP BY "Supplier_Name"
),
Supplier_Cumulative AS (
    -- STEP 2: Use Window Functions to calculate running carbon and ranking
    SELECT "Supplier_Name",
        transaction_count,
        total_spend_gbp,
        total_tco2e,
        -- Rank suppliers from highest carbon emitter to lowest
        DENSE_RANK() OVER (
            ORDER BY total_tco2e DESC
        ) AS carbon_rank,
        -- Cumulative running total of tCO2e
        SUM(total_tco2e) OVER (
            ORDER BY total_tco2e DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_total_tco2e,
        -- Grand total carbon footprint across ALL suppliers (for percentage calc)
        SUM(total_tco2e) OVER () AS grand_total_tco2e
    FROM Supplier_Totals
),
Pareto_Metrics AS (
    -- STEP 3: Calculate cumulative percentage of overall footprint
    SELECT "Supplier_Name",
        carbon_rank,
        transaction_count,
        total_spend_gbp,
        total_tco2e,
        running_total_tco2e,
        -- Cumulative % = (Running Total / Grand Total) * 100
        ROUND(
            (running_total_tco2e / grand_total_tco2e * 100)::numeric,
            2
        ) AS cumulative_carbon_pct
    FROM Supplier_Cumulative
) -- STEP 4: Final Output - Retrieve suppliers responsible for the top 80% of emissions
SELECT carbon_rank,
    "Supplier_Name",
    transaction_count,
    total_spend_gbp,
    total_tco2e,
    cumulative_carbon_pct,
    CASE
        WHEN cumulative_carbon_pct <= 80.0 THEN 'Tier 1 Priority (Top 80% Footprint)'
        ELSE 'Tail Spend / Low Priority'
    END AS supplier_priority_group
FROM Pareto_Metrics
ORDER BY carbon_rank ASC;