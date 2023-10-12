import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue import DynamicFrame


def sparkSqlQuery(glueContext, query, mapping, transformation_ctx) -> DynamicFrame:
    for alias, frame in mapping.items():
        frame.toDF().createOrReplaceTempView(alias)
    result = spark.sql(query)
    return DynamicFrame.fromDF(result, glueContext, transformation_ctx)


args = getResolvedOptions(sys.argv, ["JOB_NAME", "GCP_PROJECT_NAME", "SRC_BQ_CONN_NAME", "TGT_S3_PATH"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

 # create a df using data from bq table
sparkbq_node1 = glueContext.create_dynamic_frame.from_options(
    connection_type="custom.spark",
    connection_options={
        "table": "bigquery-public-data.covid19_open_data.covid19_open_data",
        "parentProject": args["GCP_PROJECT_NAME"], 
        "connectionName": args["SRC_BQ_CONN_NAME"],
    },
    transformation_ctx="sparkbq_node1",
)

# filter bq df using a spark sql query
bq_filter_query = "select * from myDataSource limit 10"

sql_query_filter_node1 = sparkSqlQuery(
    glueContext,
    query=bq_filter_query,
    mapping={"myDataSource": sparkbq_node1},
    transformation_ctx="sql_query_filter_node1",
)

# write df to s3 bucket as csv
s3_bucket_node1 = glueContext.write_dynamic_frame.from_options(
    frame=sql_query_filter_node1,
    connection_type="s3",
    format="csv",
    connection_options={
        "path": args["TGT_S3_PATH"],
        "partitionKeys": [],
    },
    transformation_ctx="s3_bucket_node1",
)

job.commit()
