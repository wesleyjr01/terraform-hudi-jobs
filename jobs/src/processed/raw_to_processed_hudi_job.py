import sys
from pyspark.sql.session import SparkSession
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.sql.types import *

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "target_bucket_name",
        "catalog_source_table",
        "catalog_source_database",
        "duplicate_ranking_column",
        "primary_key_column",
        "catalog_source_datasource",
    ],
)

spark = (
    SparkSession.builder.config(
        "spark.serializer", "org.apache.spark.serializer.KryoSerializer"
    )
    .config("spark.sql.hive.convertMetastoreParquet", "false")
    .getOrCreate()
)
glueContext = GlueContext(spark)
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

target_hudi_table = args["catalog_source_table"]
target_hudi_database = args["catalog_source_database"].replace("raw", "processed")

commonConfig = {
    "className": "org.apache.hudi",
    "hoodie.datasource.hive_sync.use_jdbc": "false",
    # Field used in preCombining before actual write. When two records have the same key value,
    # we will pick the one with the largest value for the precombine field.
    "hoodie.datasource.write.precombine.field": args["duplicate_ranking_column"],
    # Record key field. Value to be used as the recordKey component of HoodieKey.
    # Actual value will be obtained by invoking .toString() on the field value.
    "hoodie.datasource.write.recordkey.field": args["primary_key_column"],
    # Table name to register to Hive metastore
    "hoodie.table.name": target_hudi_table,
    "hoodie.consistency.check.enabled": "true",
    # The name of the destination database that we should sync the hudi table to.
    "hoodie.datasource.hive_sync.database": target_hudi_database,
    "hoodie.datasource.hive_sync.table": target_hudi_table,
    "hoodie.datasource.hive_sync.enable": "true",
    "hoodie.datasource.write.payload.class": "org.apache.hudi.payload.AWSDmsAvroPayload",  # Allows Hudi to process deletes (Op = 'D') from DMS
    "hoodie.datasource.hive_sync.mode": "hms",  # Hudi packaging conflict with Spark 3.x, 'hms' recommended in https://github.com/apache/hudi/issues/1751#issuecomment-920019202
    "hoodie.embed.timeline.server": "false",  # HUDI-1063/HUDI-1891 timeline server Jetty dependencies have known conflicts
    "path": f"s3://{args['target_bucket_name']}/{args['catalog_source_datasource']}/{target_hudi_database}/{target_hudi_table}",
}
unpartitionDataConfig = {
    "hoodie.datasource.hive_sync.partition_extractor_class": "org.apache.hudi.hive.NonPartitionedExtractor",
    "hoodie.datasource.write.keygenerator.class": "org.apache.hudi.keygen.NonpartitionedKeyGenerator",
}
incrementalConfig = {
    "hoodie.upsert.shuffle.parallelism": 10,
    "hoodie.datasource.write.operation": "upsert",
    "hoodie.cleaner.policy": "KEEP_LATEST_COMMITS",
    "hoodie.cleaner.commits.retained": 10,
}
combinedConf = {**commonConfig, **unpartitionDataConfig, **incrementalConfig}
glueContext.write_dynamic_frame.from_options(
    frame=glueContext.create_dynamic_frame.from_catalog(
        database=args["catalog_source_database"],
        table_name=args["catalog_source_table"],
        transformation_ctx=args["catalog_source_table"],
    ),
    connection_type="marketplace.spark",
    connection_options=combinedConf,
)
