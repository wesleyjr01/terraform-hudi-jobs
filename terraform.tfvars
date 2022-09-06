# General
aws_region = "us-east-1"

# Environment
environment = "prod"

# dl_storage_layer_variables
bucket_names = ["dl-raw-layer-cde-draft", "dl-processed-layer-cde-draft"]

# Glue Catalog Databases at Raw Layer
personality_ratings_raw_db = "personality_ratings_raw"

# Glue Jobs Hudi Jobs Metadata
# Organization metadata
processed_etl_metadata = {
  "personality" = {
    duplicate_ranking_column  = "ts"
    primary_key_column        = "userid"
    catalog_source_database   = "personality_ratings_raw"
    catalog_source_table      = "personality"
    catalog_source_datasource = "personality_ratings"
    worker_count              = 2,
  },
}
