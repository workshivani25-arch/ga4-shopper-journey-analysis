"""
Run every SQL file in /sql against BigQuery, save the results as CSV,
and draw the charts used in the README.

Usage:
    python src/run_analysis.py --project YOUR_GCP_PROJECT_ID

    # Already exported the query results as CSV from the BigQuery console?
    # Put them in outputs/data/ (named like 02_funnel_by_segment.csv) and run:
    python src/run_analysis.py --from-csv
"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
DATA_DIR = ROOT / "outputs" / "data"
CHART_DIR = ROOT / "outputs" / "charts"

BLUE = "#2F5D8C"
GREY = "#B8C2CC"
RED = "#C0504D"


# ---------------------------------------------------------------- data loading

def run_queries(project: str) -> None:
    """Execute each .sql file and save its result to outputs/data/<name>.csv."""
    from google.cloud import bigquery  # imported here so --from-csv works without it

    client = bigquery.Client(project=project)
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        print(f"Running {sql_file.name} ...")
        df = client.query(sql_file.read_text()).to_dataframe()
        out = DATA_DIR / f"{sql_file.stem}.csv"
        df.to_csv(out, index=False)
        print(f"  saved {len(df)} rows -> {out.relative_to(ROOT)}")


def load(name: str) -> pd.DataFrame:
    path = DATA_DIR / f"{name}.csv"
    if not path.exists():
        raise FileNotFoundError(f"{path} not found. Run the queries first.")
    return pd.read_csv(path)


def save(fig, name: str) -> None:
    fig.tight_layout()
    fig.savefig(CHART_DIR / f"{name}.png", dpi=160)
    plt.close(fig)
    print(f"  chart -> outputs/charts/{name}.png")


def tidy(ax) -> None:
    ax.spines[["top", "right"]].set_visible(False)


# ---------------------------------------------------------------------- charts

def chart_funnel(df: pd.DataFrame) -> None:
    """Overall funnel: how many sessions reach each step."""
    row = df[df["segment_type"] == "All"].iloc[0]
    steps = ["Viewed item", "Added to cart", "Began checkout", "Purchased"]
    values = [row["view_item_sessions"], row["add_to_cart_sessions"],
              row["checkout_sessions"], row["purchase_sessions"]]

    fig, ax = plt.subplots(figsize=(8, 4.5))
    bars = ax.barh(steps[::-1], values[::-1], color=BLUE)
    for bar, v in zip(bars, values[::-1]):
        pct = v / values[0] * 100
        ax.text(bar.get_width(), bar.get_y() + bar.get_height() / 2,
                f"  {int(v):,} ({pct:.1f}%)", va="center", fontsize=9)
    ax.set_title("Purchase funnel (sessions reaching each step)", loc="left")
    ax.set_xlabel("Sessions")
    ax.set_xlim(0, values[0] * 1.25)
    tidy(ax)
    save(fig, "01_overall_funnel")


def chart_conversion_by_segment(df: pd.DataFrame, segment_type: str, name: str) -> None:
    """Step-to-step conversion rates compared across segments."""
    sub = df[df["segment_type"] == segment_type].set_index("segment")
    cols = {"view_to_cart_pct": "View → cart",
            "cart_to_checkout_pct": "Cart → checkout",
            "checkout_to_purchase_pct": "Checkout → purchase"}
    plot = sub[list(cols)].rename(columns=cols)

    fig, ax = plt.subplots(figsize=(8, 4.5))
    plot.T.plot(kind="bar", ax=ax, rot=0, width=0.75)
    ax.set_title(f"Funnel step conversion by {segment_type.lower()}", loc="left")
    ax.set_ylabel("Conversion (%)")
    ax.legend(title=None, frameon=False)
    tidy(ax)
    save(fig, name)


def chart_abandonment(df: pd.DataFrame) -> None:
    """Where cart abandoners drop out, by device."""
    stages = {"left_at_cart": "Left at cart",
              "left_before_shipping": "Left before shipping",
              "left_before_payment": "Left before payment",
              "left_after_payment": "Left after payment"}
    plot = df.set_index("device")[list(stages)].rename(columns=stages)
    share = plot.div(plot.sum(axis=1), axis=0) * 100

    fig, ax = plt.subplots(figsize=(8, 4.5))
    share.plot(kind="barh", stacked=True, ax=ax,
               color=[RED, "#E5A15A", "#9DB4CC", GREY])
    ax.set_title("Where abandoned carts are lost (share of abandoners)", loc="left")
    ax.set_xlabel("% of abandoned sessions")
    ax.set_ylabel("")
    ax.legend(frameon=False, bbox_to_anchor=(1, 1), loc="upper left")
    tidy(ax)
    save(fig, "04_cart_abandonment_by_device")


def chart_products(df: pd.DataFrame) -> None:
    """Views vs conversion: each dot is a product."""
    colours = {"High interest, low conversion": RED,
               "Strong converter": BLUE,
               "Middle of the pack": GREY}
    fig, ax = plt.subplots(figsize=(8, 5))
    for group, g in df.groupby("product_group"):
        ax.scatter(g["views"], g["units_per_100_views"], s=22, alpha=0.8,
                   color=colours.get(group, GREY), label=group)
    # Label the five most-viewed weak converters
    weak = df[df["product_group"] == "High interest, low conversion"].nlargest(5, "views")
    for _, r in weak.iterrows():
        ax.annotate(str(r["item_name"])[:28], (r["views"], r["units_per_100_views"]),
                    fontsize=7, xytext=(4, 4), textcoords="offset points")
    ax.set_xscale("log")
    ax.set_title("Product interest vs conversion", loc="left")
    ax.set_xlabel("Product views (log scale)")
    ax.set_ylabel("Units sold per 100 views")
    ax.legend(frameon=False)
    tidy(ax)
    save(fig, "05_product_interest_vs_conversion")


def chart_rfm(df: pd.DataFrame) -> None:
    """Share of customers vs share of revenue for each RFM segment."""
    plot = df.set_index("segment")[["pct_of_customers", "pct_of_revenue"]]
    plot.columns = ["% of customers", "% of revenue"]

    fig, ax = plt.subplots(figsize=(8, 4.5))
    plot.plot(kind="barh", ax=ax, color=[GREY, BLUE])
    ax.invert_yaxis()
    ax.set_title("Customer segments: size vs revenue contribution", loc="left")
    ax.set_xlabel("%")
    ax.set_ylabel("")
    ax.legend(frameon=False)
    tidy(ax)
    save(fig, "06_rfm_segments")


# ------------------------------------------------------------------------ main

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", help="Your Google Cloud project ID")
    parser.add_argument("--from-csv", action="store_true",
                        help="Skip BigQuery and use CSVs already in outputs/data/")
    args = parser.parse_args()

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    CHART_DIR.mkdir(parents=True, exist_ok=True)

    if not args.from_csv:
        if not args.project:
            parser.error("give --project YOUR_GCP_PROJECT_ID, or use --from-csv")
        run_queries(args.project)

    print("Drawing charts ...")
    funnel = load("02_funnel_by_segment")
    chart_funnel(funnel)
    chart_conversion_by_segment(funnel, "Device", "02_conversion_by_device")
    chart_conversion_by_segment(funnel, "Customer type", "03_conversion_new_vs_returning")
    chart_abandonment(load("03_cart_abandonment"))
    chart_products(load("04_product_performance"))
    chart_rfm(load("05_rfm_segments"))
    print("Done. Fill in the Results section of README.md from outputs/data/*.csv")


if __name__ == "__main__":
    main()
