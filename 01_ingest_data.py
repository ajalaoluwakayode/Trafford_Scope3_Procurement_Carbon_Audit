from sqlalchemy import create_engine
import pandas as pd

# 1. Load Master Mapping Dictionary
mapping_df = pd.read_csv('Proclass_Mapping_Master.csv', low_memory=False)

# Filter out empty or missing labels and convert to clean uppercase string
mapping_df = mapping_df.dropna(subset=['Trafford_Proclasslabel_Unique']).copy()
mapping_df['Clean_Label'] = mapping_df['Trafford_Proclasslabel_Unique'].astype(
    str).str.strip().str.upper()

# Remove duplicates on the clean key
mapping_df = mapping_df.drop_duplicates(subset=['Clean_Label'])

# Build lookup dictionaries with guaranteed string keys
category_dict = dict(
    zip(mapping_df['Clean_Label'], mapping_df['Carbonsaver_Category_Unique']))
factor_dict = dict(
    zip(mapping_df['Clean_Label'], mapping_df['Carbon_Factors_Unique']))
master_clean_keys = [str(k) for k in category_dict.keys()]

# Function to safely map labels, handling NaNs, whitespace, case, and truncation


def resolve_mapping(raw_label):
    if pd.isna(raw_label) or raw_label is None:
        return 'Unmapped', 0.0

    label_str = str(raw_label).strip().upper()
    if not label_str or label_str in ['NAN', 'NONE', 'NULL', 'NOT CLASSIFIED']:
        return 'Unmapped', 0.0

    # 1. Exact match on normalized string
    if label_str in category_dict:
        return category_dict[label_str], factor_dict[label_str]

    # 2. Prefix matching for truncated strings (e.g., 'CLEANING & JANATORIAL : Cleani')
    if len(label_str) > 5:
        for master_key in master_clean_keys:
            if master_key.startswith(label_str) or label_str.startswith(master_key):
                return category_dict[master_key], factor_dict[master_key]

    return 'Unmapped', 0.0


# 2. File list for all 3 financial years
spend_files = {
    '2024-25': 'Trafford_Supplier_Spend_2024_25.csv',
    '2025-26': 'Trafford_Supplier_Spend_2025_26.csv',
    '2026-27': 'Trafford_Supplier_Spend_2026_27.csv'
}

all_years = []

for fy, filepath in spend_files.items():
    df = pd.read_csv(filepath, low_memory=False)
    df['Financial_Year'] = fy

    proclass_col = 'ProclassLabel' if 'ProclassLabel' in df.columns else 'Trafford_Proclasslabel_Unique'

    # Apply mapping resolution logic
    mapped_results = df[proclass_col].apply(resolve_mapping)
    df['Carbonsaver_Category'] = [res[0] for res in mapped_results]
    df['Carbon_Factor'] = [res[1] for res in mapped_results]

    # Clean numeric fields & calculate emissions
    df['Amount'] = pd.to_numeric(df['Amount'], errors='coerce').fillna(0.0)
    df['Carbon_Factor'] = pd.to_numeric(
        df['Carbon_Factor'], errors='coerce').fillna(0.0)

    df['Carbon_Emissions_kgCO2e'] = df['Amount'] * df['Carbon_Factor']
    df['Carbon_Emissions_tCO2e'] = df['Carbon_Emissions_kgCO2e'] / 1000.0

    # Report unmapped status
    unmapped_df = df[df['Carbonsaver_Category'] == 'Unmapped']
    if len(unmapped_df) > 0:
        unique_unmapped = unmapped_df[proclass_col].dropna().unique()
        print(
            f"FY {fy}: {len(unmapped_df):,} rows unmapped ({len(unique_unmapped)} unique labels: {list(unique_unmapped[:5])})")

    all_years.append(df)

# Combine all 3 financial years into one consolidated DataFrame
combined_df = pd.concat(all_years, ignore_index=True)

print("\n--- Data Ingestion & Cleaning Summary ---")
print(f"Total Rows Ingested: {len(combined_df):,}")
print(
    f"Total Scope 3 Footprint: {combined_df['Carbon_Emissions_tCO2e'].sum():,.2f} tCO2e")

# Connecting to PostgreSQL and exporting the combined DataFrame

# --- PostgreSQL Connection & Export ---
# Format: postgresql://[user]:[password]@[host]:[port]/[database_name]
# Replace 'your_postgres_password' with your actual pgAdmin/PostgreSQL password
DB_USER = "postgres"
DB_PASSWORD = "Lordmayor%401989"
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "Trafford_Scope3_db"

connection_string = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

print("\nConnecting to PostgreSQL database...")
engine = create_engine(connection_string)

# Load combined DataFrame directly into PostgreSQL
table_name = "trafford_spend_emissions_3yr"

combined_df.to_sql(
    name=table_name,
    con=engine,
    if_exists='replace',  # Replaces existing table if re-run
    index=False,
    chunksize=10000       # Writes in batches of 10k rows for efficiency
)

print(
    f"Data successfully exported to PostgreSQL table '{table_name}' in '{DB_NAME}'!")
