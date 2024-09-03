import pandas as pd
from datetime import date, timedelta, datetime
from openpyxl import Workbook
from openpyxl.utils.dataframe import dataframe_to_rows
import tkinter as tk
from tkinter import filedialog
import os

# Function to process the data with the given workbook path
def process_data(workbook_path):
    pd.set_option("mode.chained_assignment", None)

    # Step 1: Read the workbook and load the "Raw" sheet
    raw_sheet_name = "Raw"
    df_raw = pd.read_excel(workbook_path, sheet_name=raw_sheet_name)

    # Step 2: Filter 2020/1/1 < "Payment Due Date" < Current month +1
    start_day = datetime(2020, 1, 1).strftime("%Y-%m-%d")

    today = date.today()
    next_month = today.replace(day=1)

    if today.month == 12:
        next_month = next_month.replace(month=2, year=today.year + 1)
    elif today.month == 11:
        next_month = next_month.replace(month=1, year=today.year + 1)
    else:
        next_month = next_month.replace(month=today.month + 2)

    # Get the last day of the next month
    last_day = (next_month - timedelta(days=1)).strftime("%Y-%m-%d")

    df_filtered_due_date = df_raw[(df_raw["Payment Due Date"] >= start_day) & (df_raw["Payment Due Date"] <= last_day)]

    # Step 3: Filter "YRX_STATUS" where it is not equal to "Funded-Fully" and "Non Funded-Dupe"
    status_column = "YRX_STATUS"
    filter_condition = (df_filtered_due_date[status_column] != "Funded-Fully") & (df_filtered_due_date[status_column] != "Non Funded-Dupe")
    df_filtered_yrx_status = df_filtered_due_date[filter_condition].copy()

    # Step 4: Add "Aging Bucket" column based on days aging
    df_filtered_yrx_status.loc[:, "Aging Bucket"] = pd.cut(
        (pd.to_datetime(today) - df_filtered_yrx_status["Payment Due Date"]).dt.days,
        bins=[float("-inf"), 0, 30, 60, 90, 180, float("inf")],
        labels=["Current", "1 to 30", "31 to 60", "61 to 90", "91 to 180", "181+"]
    )

    # Defining Product Type
    df_filtered_yrx_status.loc[:, "Product Type"] = df_filtered_yrx_status["Order Number"].apply(
        lambda x: "NetSuite" if isinstance(x, str) and any(ns in x.lower() for ns in ["ns", "ns", "ns"])
        else "Oracle"
    )

    # Define Priority
    date_diff = today - pd.to_datetime(df_filtered_yrx_status["Payment Due Date"]).dt.date

    df_filtered_yrx_status["Priority"] = df_filtered_yrx_status.apply(
        lambda row: "P1_C60" if (pd.notnull(row["YRX_ASSIGNEE"]) and "OFD Cloud" in row["YRX_ASSIGNEE"] and date_diff[row.name] > timedelta(days=60))
        else "P1_1M" if (row["Open Amt"] > 1000000)
        else "P1_90D" if (date_diff[row.name] > timedelta(days=90))
        else "P2" if (date_diff[row.name] > timedelta(days=0))
        else "P3",
        axis=1)

    # Step 5: Filter "Deal Association Type" where it is not equal to "Future Funding" &
    # Filter "Adjustment_Terminated" is null
    df_filtered_association_type = df_filtered_yrx_status[df_filtered_yrx_status["Deal Association Type"] != "Future Funding"]
    df_filtered_nonterminated = df_filtered_association_type[df_filtered_association_type["Adjustment_Terminated"].isnull()]

    # Step 6: Filter based on "Open Amt" > 10 & Administered != 'No'
    df_filtered_admin = df_filtered_nonterminated[df_filtered_nonterminated["Administered"] != "No"]
    df_filtered_open_amt = df_filtered_admin[df_filtered_admin["Open Amt"] > 10]

    # Step 7: Create "Funder" column based on criteria
    df_filtered_open_amt.loc[:, "Funder"] = df_filtered_open_amt["Funder Name"].apply(
        lambda x:  "OFD" if any(name in x for name in ["OFD", "Servicer"])
        else "Key" if "Key" in x 
        else "BAL_US" if any(name in x for name in ["Banc of Ame", "Bank of Ame"])
        else "BAL_CA" if any(name in x for name in ["BAL Global Finance Canada"])
        else "SG" if "SG E" in x 
        else "WF" if "Wells Fa" in x 
        else "DEXT" if "Dext" in x
        else "Others"
    ).copy(deep=True)

    # Step 8: Drop the specified columns from the DataFrame
    columns_to_delete = ["Schedule Type", "Administered", "YRX_ORDER", "YRX_STATUS", "Adjustment", "CashApps Instruction", "Paid Amount-1", "Paid Date-1", "RT Number-1","Paid Amount-2","Paid Date-2","RT Number-2","Comments","Contract Num","Remit To (NS/OCL)","Remit From","Remit Ref","Remit Date","Payment Posting Status","Adjustment_Terminated"]

    df_filtered_open_amt.drop(columns=columns_to_delete, inplace=True)

    # Step 9: Iterate over unique "Funder" values and create new workbooks
    unique_funders = df_filtered_open_amt["Funder"].unique()

    for funder in unique_funders:
        # Create a new workbook for each unique "Funder"
        new_workbook = Workbook()
        new_sheet = new_workbook.active

        # Filter the data for the current "Funder"
        df_filtered_funder = df_filtered_open_amt[df_filtered_open_amt["Funder"] == funder]

        # Copy the filtered data with "Aging Bucket" column to the new workbook
        for r in dataframe_to_rows(df_filtered_funder, index=False, header=True):
            new_sheet.append(r)

        # Get the directory path of the original workbook
        original_directory = os.path.dirname(workbook_path)

        # Save the new workbook with the filtered data in the same directory as the original workbook
        funder_filename = os.path.join(original_directory, f"{funder}_{today}.xlsx")
        new_workbook.save(funder_filename)

        # Print a message for each workbook created
        log_message(f"Filtered data for {funder} saved to {funder_filename}")

    log_message("All workbooks created successfully.")

# Function to browse for the workbook path
def browse_file():
    file_path = filedialog.askopenfilename(filetypes=[("Excel files", "*.xlsx;*.xls")])
    if file_path:
        entry.delete(0, tk.END)  # Clear the entry field
        entry.insert(0, file_path)  # Set the selected file path in the entry field
        process_data(file_path)  # Process the data with the selected file path

# Function to log messages to the tkinter window
def log_message(message):
    text_area.insert(tk.END, message + "\n")  # Insert message into the text area
    text_area.see(tk.END)  # Scroll to the end of the text area

# Create a tkinter window
window = tk.Tk()
window.title("Workbook Path Input")

# Label for instructions
label = tk.Label(window, text="Please select the Excel workbook:")
label.pack()

# Entry field to display selected file path
entry = tk.Entry(window, width=50)
entry.pack()

# Button to browse for the workbook path
browse_button = tk.Button(window, text="Browse", command=browse_file)
browse_button.pack()

# Text area to display messages
text_area = tk.Text(window, height=30, width=100)
text_area.pack()

# Run the tkinter event loop
window.mainloop()
