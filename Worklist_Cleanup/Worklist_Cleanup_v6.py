# user can select file to process
# output file are set to be in the same directory as the selected file, with the date appended to the file names
# rearrange, pull the blank outstanding rows first

import pandas as pd
import re
from datetime import datetime
import os
import numpy as np
import tkinter as tk
from tkinter import filedialog

def process_file(file_path): 
    # Get the directory path of the selected file
    directory_path = os.path.dirname(file_path)

    # Get the file extension
    _, file_extension = os.path.splitext(file_path)

    # Convert the extension to lowercase for case-insensitivity
    file_extension = file_extension.lower()

    # Perform different actions based on the file extension
    if file_extension == '.xls':
        dfs = pd.read_html(file_path)
        o_df = dfs[0]
    elif file_extension == '.xlsx':
        o_df = pd.read_excel(file_path)

    blank_outstanding_condition = o_df['Outstanding Amount'].isna()
    blank_outstanding_condition |= o_df['Funding Model'] == "OFD Warehouse V2"
    blank_outstanding_different_indices_df = o_df[blank_outstanding_condition]
    blank_outstanding_different_indices_df = blank_outstanding_different_indices_df.copy()
   # blank_outstanding_different_indices_df['Outstanding Amount'] = pd.to_numeric(blank_outstanding_different_indices_df['Outstanding Amount'], errors='coerce')
    blank_outstanding_different_indices_df['Outstanding Amount'] = np.nan

    df = o_df[~(blank_outstanding_condition)]
    if df.empty:
        result_df = blank_outstanding_different_indices_df
        exception_df = df
    else:
        df = df.copy()
        df['Invoice Number'] = df['Invoice Number'].str.replace('#', '')
        df['Invoice Number'] = df['Invoice Number'].apply(lambda x: re.sub(r'[^\w\s]', ' ', str(x)) if pd.notna(x) else x)
        df['Invoice Number'] = df['Invoice Number'].apply(lambda x: re.sub(r'\s+', ' ', str(x).strip()) if pd.notna(x) else x)
        df['Invoice Number'] = df['Invoice Number'].str.replace('CM ', 'CM')
        df['Invoice Number'] = df['Invoice Number'].str.replace('DM ', 'DM')
        df['Invoice Number'] = df['Invoice Number'].str.replace('NS ', 'NS')
        df['Invoice Number'] = df['Invoice Number'].apply(lambda x: re.sub(r'\s+', ' ', str(x).strip()) if pd.notna(x) else x)

        s1 = df['Outstanding Amount'].str.split(' ').apply(lambda x: pd.Series(x) if isinstance(x, list) else pd.Series([''])).stack()
        s1 = s1.reset_index(level=-1, drop=True)
        s2 = df['Invoice Number'].str.split(' ').apply(lambda x: pd.Series(x) if isinstance(x, list) else pd.Series([''])).stack()
        s2 = s2.reset_index(level=-1, drop=True)

        s1_counts = s1.groupby(s1.index).size()
        s2_counts = s2.groupby(s2.index).size()

        different_indices = s1_counts.index[s1_counts != s2_counts]
        s1_filtered = s1[~s1.index.isin(different_indices)]
        s2_filtered = s2[~s2.index.isin(different_indices)]
        dropped_rows_df = df[df.index.isin(different_indices)]

        exception_df = df[df.index.isin(different_indices)]

        original_column_order = df.columns.tolist()
        columns_to_drop = ['Outstanding Amount', 'Invoice Number']
        df = df.drop(columns=columns_to_drop)

        s1_df = pd.DataFrame(s1_filtered, columns=['Outstanding Amount'])
        s2_df = pd.DataFrame(s2_filtered, columns=['Invoice Number'])

        if len(s1_df) != len(s2_df):
            message_text.insert(tk.END, "Warning: Row counts of invoice number and outstanding amount column are different. Please modify the original file.\n")
        else:
            combined_df = pd.concat([s1_df, s2_df], axis=1)

        merged_df= combined_df.join(df)
        merged_df['Payment Discount'] = merged_df['Payment Discount'].mask(merged_df.index.duplicated(), '')
        merged_df['Outstanding Amount'] = merged_df['Outstanding Amount'].str.replace(',', '')
        merged_df['Outstanding Amount'] = pd.to_numeric(merged_df['Outstanding Amount'], errors='coerce')

        merged_df['Payment Discount'] = pd.to_numeric(merged_df['Payment Discount'], errors='coerce')

        merged_df = merged_df[original_column_order + [col for col in merged_df.columns if col not in original_column_order]]
        result_df = pd.concat([merged_df, blank_outstanding_different_indices_df], ignore_index=True)


    today_date = datetime.today().strftime('%Y-%m-%d')
    output_file_path = os.path.join(directory_path, f'cleaned_worklist_{today_date}.xlsx')  
    result_df.to_excel(output_file_path, index=False)

    exception_file_path = os.path.join(directory_path, f'exception_{today_date}.xlsx')
    exception_df.to_excel(exception_file_path, index=False)

    unique_deal_ids_merged = result_df['Deal Id'].unique()
    unique_deal_ids_dropped = exception_df['Deal Id'].unique()
    unique_deal_ids_original = o_df['Deal Id'].unique()
    sum_payment_discount_merged = result_df['Payment Discount'].sum(skipna=True)
    sum_payment_discount_dropped = exception_df['Payment Discount'].sum(skipna=True)
    sum_payment_discount_original = o_df['Payment Discount'].sum(skipna=True)

    threshold = 0.5
    if set(unique_deal_ids_merged) | set(unique_deal_ids_dropped) == set(unique_deal_ids_original) and \
       abs((sum_payment_discount_merged + sum_payment_discount_dropped) - sum_payment_discount_original) < threshold:
        message_text.insert(tk.END, f"Successfully processed, total Deal ID count: {len(set(unique_deal_ids_original))}, cleaned Deal ID count: {len(set(unique_deal_ids_merged))}, exception Deal ID count: {len(set(unique_deal_ids_dropped))}\n")
    else:
        message_text.insert(tk.END, f"There is a mismatch in the 'Deal Id' values. total Deal ID count: {len(set(unique_deal_ids_original))}, cleaned Deal ID count: {len(set(unique_deal_ids_merged))}, exception Deal ID count: {len(set(unique_deal_ids_dropped))}\n")
    browse_button.configure(state="disabled")  # Disable the button after processing the file

def browse_file():
    file_path = filedialog.askopenfilename()
    if file_path:
        process_file(file_path)

# Create a tkinter window
window = tk.Tk()

# Set window title
window.title("File Path Input")

# Create a Text widget to display messages
message_text = tk.Text(window, height=10, width=80)
message_text.pack()

# Create a button to browse for the file
browse_button = tk.Button(window, text="Browse", command=browse_file)
browse_button.pack()

# Run the tkinter event loop
window.mainloop()

