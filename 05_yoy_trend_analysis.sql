-- =============================================================================
-- EXECUTORY DIRECTIVE 3: MULTI-YEAR YEAR-ON-YEAR (YoY) CARBON VARIANCE (FIXED)
-- Objective: Calculate absolute (tCO2e) and % emissions variance across FYs
-- =============================================================================
WITH Base_Categories AS (
    -- STEP 1: Assign a clean category name to every transaction row
    SELECT COALESCE(
            "Carbonsaver_Category",
            'Unmapped / Not Classified'
        ) AS category_name,
        "Financial_Year",
        "Amount",
        "Carbon_Emissions_tCO2e"
    FROM trafford_spend_emissions_3yr
    WHERE "Financial_Year" IS NOT NULL
),
Yearly_Category_Totals AS (
    -- STEP 2: Aggregate spend and emissions by category and financial year
    SELECT category_name,
        "Financial_Year",
        COUNT(*) AS transaction_count,
        ROUND(SUM("Amount")::numeric, 2) AS yearly_spend_gbp,
        ROUND(SUM("Carbon_Emissions_tCO2e")::numeric, 2) AS yearly_tco2e
    FROM Base_Categories
    GROUP BY category_name,
        "Financial_Year"
),
YoY_Calculations AS (
    -- STEP 3: Apply LAG() window function partitioned cleanly by category_name
    SELECT category_name,
        "Financial_Year",
        transaction_count,
        yearly_spend_gbp,
        yearly_tco2e,
        -- Retrieve previous year's emissions for the exact same category
        LAG(yearly_tco2e, 1) OVER (
            PARTITION BY category_name
            ORDER BY "Financial_Year" ASC
        ) AS prior_year_tco2e,
        -- Retrieve previous year's spend
        LAG(yearly_spend_gbp, 1) OVER (
            PARTITION BY category_name
            ORDER BY "Financial_Year" ASC
        ) AS prior_year_spend_gbp
    FROM Yearly_Category_Totals
) -- STEP 4: Output absolute emissions delta and percentage YoY growth rate
SELECT category_name,
    "Financial_Year",
    transaction_count,
    yearly_spend_gbp,
    yearly_tco2e,
    COALESCE(prior_year_tco2e, 0.00) AS prior_year_tco2e,
    -- Absolute Carbon Change (Delta tCO2e)
    ROUND(
        (
            yearly_tco2e - COALESCE(prior_year_tco2e, yearly_tco2e)
        )::numeric,
        2
    ) AS carbon_change_tco2e,
    -- Percentage YoY Variance Formula: ((Current - Prior) / Prior) * 100
    CASE
        WHEN prior_year_tco2e IS NULL
        OR prior_year_tco2e = 0 THEN 0.00
        ELSE ROUND(
            (
                (yearly_tco2e - prior_year_tco2e) / prior_year_tco2e * 100.0
            )::numeric,
            2
        )
    END AS yoy_carbon_growth_pct,
    -- Directional trajectory tag for reporting
    CASE
        WHEN prior_year_tco2e IS NULL THEN 'Baseline Year (FY 2024-25)'
        WHEN yearly_tco2e > prior_year_tco2e THEN 'Carbon Inflation (Increasing)'
        WHEN yearly_tco2e < prior_year_tco2e THEN 'Carbon Reduction (Decreasing)'
        ELSE 'Stable'
    END AS trajectory_status
FROM YoY_Calculations
ORDER BY category_name ASC,
    "Financial_Year" ASC;