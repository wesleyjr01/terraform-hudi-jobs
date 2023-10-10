# https://aws-bigdata-blog.s3.amazonaws.com/artifacts/hudi-on-glue/CodeScripts/HudiJob.py
import sys
import os
import json

from pyspark.context import SparkContext
from pyspark.sql.session import SparkSession
from pyspark.sql.functions import concat, col, lit, to_timestamp

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

import boto3
from botocore.exceptions import ClientError

args = getResolvedOptions(sys.argv, ['JOB_NAME'])

spark = SparkSession.builder.config('spark.serializer','org.apache.spark.serializer.KryoSerializer').getOrCreate()
glueContext = GlueContext(spark.sparkContext)
job = Job(glueContext)
job.init(args['JOB_NAME'], args)
logger = glueContext.get_logger()

logger.info('Initialization.')
glueClient = boto3.client('glue')
ssmClient = boto3.client('ssm')
redshiftDataClient = boto3.client('redshift-data')

logger.info('Fetching configuration.')
region = os.environ['AWS_DEFAULT_REGION']

curatedS3BucketName = ssmClient.get_parameter(Name='lakehouse-curated-s3-bucket-name')['Parameter']['Value']
rawS3BucketName = ssmClient.get_parameter(Name='lakehouse-raw-s3-bucket-name')['Parameter']['Value']
hudiStorageType = ssmClient.get_parameter(Name='lakehouse-hudi-storage-type')['Parameter']['Value']

dropColumnList = ['db','table_name','Op']

logger.info('Getting list of schema.tables that have changed.')
changeTableListDyf = glueContext.create_dynamic_frame_from_options(connection_type = 's3', connection_options = {'paths': ['s3://'+rawS3BucketName], 'groupFiles': 'inPartition', 'recurse':True}, format = 'parquet', format_options={}, transformation_ctx = 'changeTableListDyf')

logger.info('Processing starts.')
if(changeTableListDyf.count() > 0):
    logger.info('Got new files to process.')
    changeTableList = changeTableListDyf.toDF().select('schema_name','table_name').distinct().rdd.map(lambda row : row.asDict()).collect()

    for dbName in set([d['schema_name'] for d in changeTableList]):
        spark.sql('CREATE DATABASE IF NOT EXISTS ' + dbName)
        redshiftDataClient.execute_statement(ClusterIdentifier='lakehouse-redshift-cluster', Database='lakehouse_dw', DbUser='rs_admin', Sql='CREATE EXTERNAL SCHEMA IF NOT EXISTS ' + dbName + ' FROM DATA CATALOG DATABASE \'' + dbName + '\' REGION \'' + region + '\' IAM_ROLE \'' + boto3.client('iam').get_role(RoleName='LakeHouseRedshiftGlueAccessRole')['Role']['Arn'] + '\'')

    for i in changeTableList:
        logger.info('Looping for ' + i['schema_name'] + '.' + i['table_name'])
        dbName = i['schema_name']
        tableNameCatalogCheck = ''
        tableName = i['table_name']
        if(hudiStorageType == 'MoR'):
            tableNameCatalogCheck = i['table_name'] + '_ro' #Assumption is that if _ro table exists then _rt table will also exist. Hence we are checking only for _ro.
        else:
            tableNameCatalogCheck = i['table_name'] #The default config in the CF template is CoW. So assumption is that if the user hasn't explicitly requested to create MoR storage type table then we will create CoW tables. Again, if the user overwrites the config with any value other than 'MoR' we will create CoW storage type tables.
        isTableExists = False
        isPrimaryKey = False
        isPartitionKey = False
        primaryKey = ''
        partitionKey = ''
        try:
            glueClient.get_table(DatabaseName=dbName,Name=tableNameCatalogCheck)
            isTableExists = True
            logger.info(dbName + '.' + tableNameCatalogCheck + ' exists.')
        except ClientError as e:
            if e.response['Error']['Code'] == 'EntityNotFoundException':
                isTableExists = False
                logger.info(dbName + '.' + tableNameCatalogCheck + ' does not exist. Table will be created.')
        try:
            table_config = json.loads(ssmClient.get_parameter(Name='lakehouse-table-' + dbName + '.' + tableName)['Parameter']['Value'])
            try:
                primaryKey = table_config['primaryKey']
                isPrimaryKey = True
                logger.info('Primary key:' + primaryKey)
            except KeyError as e:
                isPrimaryKey = False
                logger.info('Primary key not found. An append only glueparquet table will be created.')
            try:
                partitionKey = table_config['partitionKey']
                isPartitionKey = True
                logger.info('Partition key:' + partitionKey)
            except KeyError as e:
                isPartitionKey = False
                logger.info('Partition key not found. Partitions will not be created.')
        except ClientError as e:    
            if e.response['Error']['Code'] == 'ParameterNotFound':
                isPrimaryKey = False
                isPartitionKey = False
                logger.info('Config for ' + dbName + '.' + tableName + ' not found in parameter store. Non partitioned append only table will be created.')

        inputDyf = glueContext.create_dynamic_frame_from_options(connection_type = 's3', connection_options = {'paths': ['s3://' + rawS3BucketName + '/' + dbName + '/' + tableName], 'groupFiles': 'none', 'recurse':True}, format = 'parquet',transformation_ctx = tableName)
        
        inputDf = inputDyf.toDF().withColumn('update_ts_dms',to_timestamp(col('update_ts_dms')))
        
        targetPath = 's3://' + curatedS3BucketName + '/' + dbName + '/' + tableName

        morConfig = {'hoodie.datasource.write.storage.type': 'MERGE_ON_READ', 'hoodie.compact.inline': 'false', 'hoodie.compact.inline.max.delta.commits': 20, 'hoodie.parquet.small.file.limit': 0}

        commonConfig = {'className' : 'org.apache.hudi', 'hoodie.datasource.hive_sync.use_jdbc':'false', 'hoodie.datasource.write.precombine.field': 'update_ts_dms', 'hoodie.datasource.write.recordkey.field': primaryKey, 'hoodie.table.name': tableName, 'hoodie.consistency.check.enabled': 'true', 'hoodie.datasource.hive_sync.database': dbName, 'hoodie.datasource.hive_sync.table': tableName, 'hoodie.datasource.hive_sync.enable': 'true'}

        partitionDataConfig = {'hoodie.datasource.write.partitionpath.field': partitionKey, 'hoodie.datasource.hive_sync.partition_extractor_class': 'org.apache.hudi.hive.MultiPartKeysValueExtractor', 'hoodie.datasource.hive_sync.partition_fields': partitionKey}
                     
        unpartitionDataConfig = {'hoodie.datasource.hive_sync.partition_extractor_class': 'org.apache.hudi.hive.NonPartitionedExtractor', 'hoodie.datasource.write.keygenerator.class': 'org.apache.hudi.keygen.NonpartitionedKeyGenerator'}
        
        incrementalConfig = {'hoodie.upsert.shuffle.parallelism': 20, 'hoodie.datasource.write.operation': 'upsert', 'hoodie.cleaner.policy': 'KEEP_LATEST_COMMITS', 'hoodie.cleaner.commits.retained': 10}
        
        initLoadConfig = {'hoodie.bulkinsert.shuffle.parallelism': 3, 'hoodie.datasource.write.operation': 'bulk_insert'}
        
        deleteDataConfig = {'hoodie.datasource.write.payload.class': 'org.apache.hudi.common.model.EmptyHoodieRecordPayload'}

        if(hudiStorageType == 'MoR'):
            commonConfig = {**commonConfig, **morConfig}
            logger.info('MoR config appended to commonConfig.')
        
        combinedConf = {}

        if(isPrimaryKey):
            logger.info('Going the Hudi way.')
            if(isTableExists):
                logger.info('Incremental load.')
                outputDf = inputDf.filter("Op != 'D'").drop(*dropColumnList)
                if outputDf.count() > 0:
                    logger.info('Upserting data.')
                    if (isPartitionKey):
                        logger.info('Writing to partitioned Hudi table.')
                        outputDf = outputDf.withColumn(partitionKey,concat(lit(partitionKey+'='),col(partitionKey)))
                        combinedConf = {**commonConfig, **partitionDataConfig, **incrementalConfig}
                        outputDf.write.format('org.apache.hudi').options(**combinedConf).mode('Append').save(targetPath)
                    else:
                        logger.info('Writing to unpartitioned Hudi table.')
                        combinedConf = {**commonConfig, **unpartitionDataConfig, **incrementalConfig}
                        outputDf.write.format('org.apache.hudi').options(**combinedConf).mode('Append').save(targetPath)
                outputDf_deleted = inputDf.filter("Op = 'D'").drop(*dropColumnList)
                if outputDf_deleted.count() > 0:
                    logger.info('Some data got deleted.')
                    if (isPartitionKey):
                        logger.info('Deleting from partitioned Hudi table.')
                        outputDf_deleted = outputDf_deleted.withColumn(partitionKey,concat(lit(partitionKey+'='),col(partitionKey)))
                        combinedConf = {**commonConfig, **partitionDataConfig, **incrementalConfig, **deleteDataConfig}
                        outputDf_deleted.write.format('org.apache.hudi').options(**combinedConf).mode('Append').save(targetPath)
                    else:
                        logger.info('Deleting from unpartitioned Hudi table.')
                        combinedConf = {**commonConfig, **unpartitionDataConfig, **incrementalConfig, **deleteDataConfig}
                        outputDf_deleted.write.format('org.apache.hudi').options(**combinedConf).mode('Append').save(targetPath)
            else:
                outputDf = inputDf.drop(*dropColumnList)
                if outputDf.count() > 0:
                    logger.info('Inital load.')
                    if (isPartitionKey):
                        logger.info('Writing to partitioned Hudi table.')
                        outputDf = outputDf.withColumn(partitionKey,concat(lit(partitionKey+'='),col(partitionKey)))
                        combinedConf = {**commonConfig, **partitionDataConfig, **initLoadConfig}
                        outputDf.write.format('org.apache.hudi').options(**combinedConf).mode('Overwrite').save(targetPath)
                    else:
                        logger.info('Writing to unpartitioned Hudi table.')
                        combinedConf = {**commonConfig, **unpartitionDataConfig, **initLoadConfig}
                        outputDf.write.format('org.apache.hudi').options(**combinedConf).mode('Overwrite').save(targetPath)
        else:
            if (isPartitionKey):
                logger.info('Writing to partitioned glueparquet table.')
                sink = glueContext.getSink(connection_type = 's3', path= targetPath, enableUpdateCatalog = True, updateBehavior = 'UPDATE_IN_DATABASE', partitionKeys=[partitionKey])
            else:
                logger.info('Writing to unpartitioned glueparquet table.')
                sink = glueContext.getSink(connection_type = 's3', path= targetPath, enableUpdateCatalog = True, updateBehavior = 'UPDATE_IN_DATABASE')
            sink.setFormat('glueparquet')
            sink.setCatalogInfo(catalogDatabase = dbName, catalogTableName = tableName)
            outputDyf = DynamicFrame.fromDF(inputDf.drop(*dropColumnList), glueContext, 'outputDyf')
            sink.writeFrame(outputDyf)

job.commit()
