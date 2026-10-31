# How to run this project

Two options. **Option A** needs no installation and works in a browser. **Option B** runs everything in one go from your computer.

BigQuery's free **sandbox** is enough: no credit card, and these queries sit well inside the free 1 TB of queries per month.

---

## Step 0 – Set up BigQuery (once)

1. Go to console.cloud.google.com and sign in with your Google account.
2. Create a new project (e.g. `ga4-shopper-analysis`). Note the **Project ID**.
3. Open **BigQuery** from the menu. If asked, accept the sandbox.
4. In the Explorer panel, click **+ Add → Star a project by name**, enter `bigquery-public-data`, and find `ga4_obfuscated_sample_ecommerce`.

## Option A – Run in the BigQuery console (easiest)

For each file in `sql/`, in order:

1. Open a new query tab, paste the file contents, click **Run**.
2. Click **Save results → CSV (local file)**.
3. Rename the file to match the SQL file (e.g. `02_funnel_by_segment.csv`) and put it in `outputs/data/`.

Then draw the charts:

```bash
pip install pandas matplotlib
python src/run_analysis.py --from-csv
```

## Option B – Run everything from Python

```bash
pip install -r requirements.txt
gcloud auth application-default login      # opens a browser to sign in
python src/run_analysis.py --project YOUR_PROJECT_ID
```

## Output

- Query results are saved as CSV files in `outputs/data/`.
- Charts are saved as PNG files in `outputs/charts/`.
