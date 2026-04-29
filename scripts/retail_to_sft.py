# scripts/retail_to_sft.py
"""
Convert the Online Retail dataset into a clean conversational SFT dataset.

Inputs:
  - CSV exported from Online Retail.xlsx

Outputs:
  - train_jsonl/              JSONL messages format for Unsloth conversational SFT
  - eval_jsonl/               JSONL messages format for evaluation
  - clean_purchases_parquet/  cleaned transaction data for audit/RAG/reporting
  - eda/                      small CSV summaries for report figures
  - samples/                  small preview files for report/debugging

Run locally:
  spark-submit scripts/retail_to_sft.py \
    --input data/online_retail.csv \
    --output out/retail_sft_test

Run on EMR:
  spark-submit s3://BUCKET/scripts/retail_to_sft.py \
    --input s3://BUCKET/data/raw/online_retail.csv \
    --output s3://BUCKET/data/processed/retail_sft
"""

import argparse
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType

SYSTEM_PROMPT = (
    "You are a helpful ecommerce shopping assistant. "
    "Use the provided historical retail context to answer shopping, order, "
    "product, and recommendation questions. Be concise and do not invent live "
    "inventory, shipping status, or real-time prices."
)


def build_messages(user_col, assistant_col):
    """Return a messages array compatible with chat/conversational SFT."""
    return F.array(
        F.struct(F.lit("system").alias("role"), F.lit(SYSTEM_PROMPT).alias("content")),
        F.struct(F.lit("user").alias("role"), user_col.alias("content")),
        F.struct(F.lit("assistant").alias("role"), assistant_col.alias("content")),
    )


def write_single_text(df, path):
    """Write a text dataframe as one part file for easier review and upload."""
    df.coalesce(1).write.mode("overwrite").text(path)


def write_single_csv(df, path):
    """Write a small CSV dataframe as one part file."""
    df.coalesce(1).write.mode("overwrite").option("header", True).csv(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Input CSV path, local or s3://")
    parser.add_argument("--output", required=True, help="Output directory, local or s3://")
    parser.add_argument("--max_orders", type=int, default=20000)
    parser.add_argument("--max_products", type=int, default=5000)
    parser.add_argument("--max_recs", type=int, default=5000)
    parser.add_argument("--max_cancellations", type=int, default=3000)
    parser.add_argument("--max_basket_size_for_pairs", type=int, default=30)
    args = parser.parse_args()

    spark = (
        SparkSession.builder
        .appName("online-retail-to-conversational-sft")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    # -----------------------------
    # 1. Load raw CSV
    # -----------------------------
    raw = (
        spark.read
        .option("header", True)
        .option("inferSchema", True)
        .option("timestampFormat", "yyyy-MM-dd HH:mm:ss")
        .csv(args.input)
    )

    # Normalize names/types. CSV inference can vary, so cast explicitly.
    df = (
        raw.select(
            F.col("InvoiceNo").cast("string").alias("InvoiceNo"),
            F.col("StockCode").cast("string").alias("StockCode"),
            F.trim(F.col("Description").cast("string")).alias("Description"),
            F.col("Quantity").cast("int").alias("Quantity"),
            F.to_timestamp(F.col("InvoiceDate")).alias("InvoiceDate"),
            F.col("UnitPrice").cast("double").alias("UnitPrice"),
            F.col("CustomerID").cast("string").alias("CustomerID"),
            F.col("Country").cast("string").alias("Country"),
        )
        .filter(F.col("InvoiceNo").isNotNull())
        .filter(F.col("StockCode").isNotNull())
    )

    raw_count = df.count()

    # -----------------------------
    # 2. Clean and split transaction types
    # -----------------------------
    # Cancellations in this dataset often have invoice numbers that start with C.
    cancellations = df.filter(
        F.col("InvoiceNo").startswith("C")
        | (F.col("Quantity") <= 0)
        | (F.col("UnitPrice") < 0)
    )

    purchases = (
        df.filter(~F.col("InvoiceNo").startswith("C"))
        .filter(F.col("Description").isNotNull())
        .filter(F.length(F.col("Description")) > 2)
        .filter(F.col("Quantity") > 0)
        .filter(F.col("UnitPrice") > 0)
        .dropDuplicates([
            "InvoiceNo", "StockCode", "Description", "Quantity", "InvoiceDate", "UnitPrice", "CustomerID"
        ])
    )

    purchase_count = purchases.count()
    cancellation_count = cancellations.count()

    # Canonical product name: choose the most frequent description for each stock code.
    desc_counts = purchases.groupBy("StockCode", "Description").count()
    desc_window = Window.partitionBy("StockCode").orderBy(F.desc("count"), F.asc("Description"))

    product_names = (
        desc_counts
        .withColumn("rn", F.row_number().over(desc_window))
        .filter(F.col("rn") == 1)
        .select("StockCode", F.col("Description").alias("ProductName"))
    )

    line_items = (
        purchases.drop("Description")
        .join(product_names, on="StockCode", how="left")
        .withColumn("LineTotal", F.col("Quantity") * F.col("UnitPrice"))
        .filter(F.col("ProductName").isNotNull())
    )

    # Save cleaned data for audit and future retrieval/database use.
    line_items.write.mode("overwrite").parquet(f"{args.output}/clean_purchases_parquet")

    # -----------------------------
    # 3. Build product information examples
    # -----------------------------
    product_stats = (
        line_items.groupBy("StockCode", "ProductName")
        .agg(
            F.countDistinct("InvoiceNo").alias("order_count"),
            F.sum("Quantity").alias("units_sold"),
            F.avg("UnitPrice").alias("avg_price"),
            F.countDistinct("Country").alias("country_count"),
        )
        .orderBy(F.desc("order_count"))
        .limit(args.max_products)
    )

    product_examples = (
        product_stats
        .withColumn(
            "user_text",
            F.concat(F.lit("Tell me about the product: "), F.col("ProductName"), F.lit(".")),
        )
        .withColumn(
            "assistant_text",
            F.concat(
                F.lit("Product: "), F.col("ProductName"),
                F.lit(". In the historical data, it appeared in "),
                F.col("order_count").cast("string"),
                F.lit(" orders and sold "),
                F.col("units_sold").cast("string"),
                F.lit(" units. The average historical unit price was £"),
                F.format_number(F.col("avg_price"), 2),
                F.lit(". Use this as historical context, not live inventory."),
            ),
        )
        .withColumn("example_type", F.lit("product_info"))
        .withColumn("messages", build_messages(F.col("user_text"), F.col("assistant_text")))
        .select("example_type", "messages")
    )

    # -----------------------------
    # 4. Build order inquiry examples
    # -----------------------------
    item_text = F.concat(
        F.col("ProductName"),
        F.lit(" x"),
        F.col("Quantity").cast("string"),
        F.lit(" at £"),
        F.format_number(F.col("UnitPrice"), 2),
    )

    order_base = (
        line_items.withColumn("item_text", item_text)
        .groupBy("InvoiceNo", "Country")
        .agg(
            F.slice(F.collect_list("item_text"), 1, 12).alias("items"),
            F.sum("LineTotal").alias("order_total"),
            F.countDistinct("StockCode").alias("unique_items"),
            F.min("InvoiceDate").alias("invoice_date"),
        )
        .orderBy(F.rand(seed=42))
        .limit(args.max_orders)
    )

    order_examples = (
        order_base
        .withColumn("user_text", F.concat(F.lit("What is in order invoice "), F.col("InvoiceNo"), F.lit("?")))
        .withColumn(
            "assistant_text",
            F.concat(
                F.lit("Invoice "), F.col("InvoiceNo"),
                F.lit(" contains "), F.col("unique_items").cast("string"),
                F.lit(" unique product(s): "), F.concat_ws("; ", F.col("items")),
                F.lit(". The estimated historical total is £"),
                F.format_number(F.col("order_total"), 2),
                F.lit(". This is based only on historical transaction data."),
            ),
        )
        .withColumn("example_type", F.lit("order_inquiry"))
        .withColumn("messages", build_messages(F.col("user_text"), F.col("assistant_text")))
        .select("example_type", "messages")
    )

    # -----------------------------
    # 5. Build recommendation examples from co-purchases
    # -----------------------------
    basket_sizes = line_items.groupBy("InvoiceNo").agg(F.countDistinct("StockCode").alias("basket_size"))

    basket_items = (
        line_items.select("InvoiceNo", "StockCode", "ProductName")
        .join(basket_sizes, on="InvoiceNo", how="inner")
        .filter(F.col("basket_size") <= args.max_basket_size_for_pairs)
        .dropDuplicates(["InvoiceNo", "StockCode"])
    )

    a = basket_items.alias("a")
    b = basket_items.alias("b")

    pairs = (
        a.join(b, on="InvoiceNo")
        .filter(F.col("a.StockCode") < F.col("b.StockCode"))
        .select(
            F.col("a.StockCode").alias("a_code"),
            F.col("a.ProductName").alias("a_name"),
            F.col("b.StockCode").alias("b_code"),
            F.col("b.ProductName").alias("b_name"),
        )
    )

    directed_pairs = (
        pairs.select(
            F.col("a_code").alias("src_code"),
            F.col("a_name").alias("src_name"),
            F.col("b_name").alias("rec_name"),
        )
        .unionByName(
            pairs.select(
                F.col("b_code").alias("src_code"),
                F.col("b_name").alias("src_name"),
                F.col("a_name").alias("rec_name"),
            )
        )
    )

    pair_counts = directed_pairs.groupBy("src_code", "src_name", "rec_name").agg(F.count("*").alias("score"))
    rec_window = Window.partitionBy("src_code").orderBy(F.desc("score"), F.asc("rec_name"))

    top_recs = (
        pair_counts
        .withColumn("rn", F.row_number().over(rec_window))
        .filter(F.col("rn") <= 5)
        .groupBy("src_code", "src_name")
        .agg(F.collect_list("rec_name").alias("recs"))
        .filter(F.size("recs") >= 2)
        .orderBy(F.rand(seed=7))
        .limit(args.max_recs)
    )

    rec_examples = (
        top_recs
        .withColumn(
            "user_text",
            F.concat(
                F.lit("I like "), F.col("src_name"),
                F.lit(". Recommend similar or complementary products."),
            ),
        )
        .withColumn(
            "assistant_text",
            F.concat(
                F.lit("Based on historical co-purchases, customers who bought "),
                F.col("src_name"),
                F.lit(" also often bought: "),
                F.concat_ws(", ", F.col("recs")),
                F.lit(". These are historical recommendations, not live stock guarantees."),
            ),
        )
        .withColumn("example_type", F.lit("recommendation"))
        .withColumn("messages", build_messages(F.col("user_text"), F.col("assistant_text")))
        .select("example_type", "messages")
    )

    # -----------------------------
    # 6. Build cancellation / return examples
    # -----------------------------
    cancellation_base = (
        cancellations.filter(F.col("Description").isNotNull())
        .groupBy("InvoiceNo")
        .agg(
            F.slice(F.collect_list(F.col("Description")), 1, 8).alias("items"),
            F.sum("Quantity").alias("net_quantity"),
        )
        .orderBy(F.rand(seed=99))
        .limit(args.max_cancellations)
    )

    cancellation_examples = (
        cancellation_base
        .withColumn("user_text", F.concat(F.lit("What does invoice "), F.col("InvoiceNo"), F.lit(" mean?")))
        .withColumn(
            "assistant_text",
            F.concat(
                F.lit("Invoice "), F.col("InvoiceNo"),
                F.lit(" appears to be a cancellation or return record in the historical data. "),
                F.lit("The related item descriptions include: "),
                F.concat_ws("; ", F.col("items")),
                F.lit(". For a real customer case, check the live order system before taking action."),
            ),
        )
        .withColumn("example_type", F.lit("cancellation_or_return"))
        .withColumn("messages", build_messages(F.col("user_text"), F.col("assistant_text")))
        .select("example_type", "messages")
    )

    # -----------------------------
    # 7. Combine, dedupe, split, and output JSONL
    # -----------------------------
    examples = (
        product_examples
        .unionByName(order_examples)
        .unionByName(rec_examples)
        .unionByName(cancellation_examples)
        .withColumn("json", F.to_json(F.struct("messages")))
        .dropDuplicates(["json"])
    )

    train, eval_df = examples.randomSplit([0.9, 0.1], seed=42)
    train = train.withColumn("split", F.lit("train"))
    eval_df = eval_df.withColumn("split", F.lit("eval"))
    final_examples = train.unionByName(eval_df)

    write_single_text(train.select(F.col("json").alias("value")), f"{args.output}/train_jsonl")
    write_single_text(eval_df.select(F.col("json").alias("value")), f"{args.output}/eval_jsonl")

    # -----------------------------
    # 8. EDA outputs for report figures
    # -----------------------------
    # Approx token count: useful enough for split/token-length distribution figure.
    # This is not exact tokenizer count; exact count can be added in the fine-tuning notebook.
    approx_tokens = F.ceil(F.length(F.col("json")) / F.lit(4)).cast(IntegerType())
    eda_examples = final_examples.withColumn("approx_tokens", approx_tokens)

    split_counts = eda_examples.groupBy("split", "example_type").count().orderBy("split", "example_type")
    write_single_csv(split_counts, f"{args.output}/eda/example_type_by_split")

    token_summary = (
        eda_examples.groupBy("split")
        .agg(
            F.count("*").alias("sample_count"),
            F.min("approx_tokens").alias("min_tokens"),
            F.expr("percentile_approx(approx_tokens, 0.25)").alias("p25_tokens"),
            F.expr("percentile_approx(approx_tokens, 0.50)").alias("median_tokens"),
            F.expr("percentile_approx(approx_tokens, 0.75)").alias("p75_tokens"),
            F.max("approx_tokens").alias("max_tokens"),
        )
        .orderBy("split")
    )
    write_single_csv(token_summary, f"{args.output}/eda/token_length_summary")

    token_hist = (
        eda_examples
        .withColumn(
            "token_bucket",
            F.when(F.col("approx_tokens") < 100, F.lit("000-099"))
            .when(F.col("approx_tokens") < 200, F.lit("100-199"))
            .when(F.col("approx_tokens") < 300, F.lit("200-299"))
            .when(F.col("approx_tokens") < 400, F.lit("300-399"))
            .when(F.col("approx_tokens") < 600, F.lit("400-599"))
            .otherwise(F.lit("600+")),
        )
        .groupBy("split", "token_bucket")
        .count()
        .orderBy("split", "token_bucket")
    )
    write_single_csv(token_hist, f"{args.output}/eda/token_length_histogram")

    cleaning_summary = spark.createDataFrame(
        [
            ("raw_rows", raw_count),
            ("clean_purchase_rows", purchase_count),
            ("cancellation_or_invalid_rows", cancellation_count),
        ],
        ["metric", "value"],
    )
    write_single_csv(cleaning_summary, f"{args.output}/eda/cleaning_summary")

    top_products = product_stats.select(
        "StockCode", "ProductName", "order_count", "units_sold", F.round("avg_price", 2).alias("avg_price")
    ).orderBy(F.desc("order_count")).limit(25)
    write_single_csv(top_products, f"{args.output}/eda/top_products")

    # Save a few examples for quick inspection/report sample.
    write_single_text(
        final_examples.select(F.col("json").alias("value")).limit(20),
        f"{args.output}/samples/sample_jsonl",
    )

    print("DONE")
    print(f"Raw rows: {raw_count}")
    print(f"Clean purchase rows: {purchase_count}")
    print(f"Cancellation/invalid rows: {cancellation_count}")
    print(f"Output written to: {args.output}")

    spark.stop()


if __name__ == "__main__":
    main()
