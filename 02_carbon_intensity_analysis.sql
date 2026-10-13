-- =============================================================================
-- ANALYSIS 2: CARBON INTENSITY RATIO BY CATEGORY
-- Objective: Rank categories by carbon intensity (kgCO2e per £ spend)
-- =============================================================================
WITH Category_Metrics AS (
    SELECT COALESCE(
            "Carbonsaver_Category",
            'Unmapped / Not Classified'
        ) AS category_name,
        COUNT(*) AS transaction_count,
        SUM("Amount") AS total_spend_gbp,
        SUM("Carbon_Emissions_tCO2e") AS total_tco2e
    FROM trafford_spend_emissions_3yr
    GROUP BY COALESCE(
            "Carbonsaver_Category",
            'Unmapped / Not Classified'
        ) -- Filter out negative/zero adjustments so they don't skew intensity ratios
    HAVING SUM("Amount") > 0
),
Intensity_Calculations AS (
    SELECT category_name,
        transaction_count,
        ROUND(total_spend_gbp::numeric, 2) AS total_spend_gbp,
        ROUND(total_tco2e::numeric, 2) AS total_tco2e,
        -- Carbon Intensity Formula: (tCO2e * 1000 kg) / Spend GBP
        ROUND(
            ((total_tco2e * 1000.0) / total_spend_gbp)::numeric,
            4
        ) AS kgco2e_per_gbp,
        -- Portfolio Share Metrics
        SUM(total_spend_gbp) OVER () AS grand_total_spend,
        SUM(total_tco2e) OVER () AS grand_total_tco2e
    FROM Category_Metrics
)
SELECT DENSE_RANK() OVER (
        ORDER BY kgco2e_per_gbp DESC
    ) AS intensity_rank,
    category_name,
    transaction_count,
    total_spend_gbp,
    total_tco2e,
    kgco2e_per_gbp,
    -- Category share of overall spend and overall carbon
    ROUND(
        (total_spend_gbp / grand_total_spend * 100)::numeric,
        2
    ) AS spend_share_pct,
    ROUND(
        (total_tco2e / grand_total_tco2e * 100)::numeric,
        2
    ) AS carbon_share_pct,
    -- Categorization logic for procurement strategy
    CASE
        WHEN kgco2e_per_gbp >= 0.50 THEN 'High Carbon Intensity (Priority Decarbonization)'
        WHEN kgco2e_per_gbp BETWEEN 0.15 AND 0.49 THEN 'Moderate Intensity'
        ELSE 'Low Carbon Intensity (Commercial Focus)'
    END AS intensity_classification
FROM Intensity_Calculations
ORDER BY kgco2e_per_gbp DESC;