```bash
#!/usr/bin/python3

##################################################
# Requires the python3 plugin to be installed
##################################################

print("public_dirtree script has started", flush=True)
import os
import sys
import subprocess
import importlib
import threading
from queue import Queue
from collections import defaultdict
import fnmatch
from datetime import datetime

    #### DON'T CHANGE ANYTHING ABOVE HERE ####

# ==== CONFIGURATION ====
share_names = ["mymedia", "data", "domains", "system"]
output_file = "/mnt/user/data/computer/unraidstuff/dirtree/dirtree.xlsx"
old_file = "/mnt/user/data/computer/unraidstuff/dirtree/dirtree_old.xlsx"
diff_file = "/mnt/user/data/computer/unraidstuff/dirtree/dirtree_differences.xlsx"
num_threads = 8
keep_count = 7  # Number of files to keep of each file

# Paths to skip (wildcards supported)
skip_paths = [
    "/mnt/disk*/mymedia/downloads*",
    "/mnt/disk*/mymedia/tdarr_cache*"
]

# Explicit keep paths
keep_paths = [
    "/mnt/cache/data/nextcloud/jcofer555/files",
    "/mnt/cache/data/nextcloud/juhl/files"
]

    #### DON'T CHANGE ANYTHING BELOW HERE ####

# ---- Dependency check  ----
required_packages = ["pandas", "openpyxl"]

def check_and_install(pkg):
    try:
        importlib.import_module(pkg)
        print(f"{pkg} is already installed")
    except ImportError:
        print(f"{pkg} not found, installing...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", pkg])
            print(f"Successfully installed {pkg}")
        except subprocess.CalledProcessError:
            print(f"Failed to install {pkg}. Please install manually.")
            sys.exit(1)

for package in required_packages:
    check_and_install(package)

# Import now that we know they're installed
import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import Font, PatternFill

# ---- Add today's date to filenames ----
today = datetime.now().strftime("%d-%m-%Y")
def dated_filename(path):
    base, ext = os.path.splitext(path)
    return f"{base}-{today}{ext}"

output_file = dated_filename(output_file)
old_file = dated_filename(old_file)
diff_file = dated_filename(diff_file)

disk_queue = Queue()
results = []
lock = threading.Lock()

# ==== original functions ====
def cleanup_old_files():
    """Keep only the newest N files for each file type (dirtree, dirtree_old, dirtree_differences)."""
    base_path = os.path.dirname(output_file)
    prefixes = ["dirtree", "dirtree_old", "dirtree_differences"]

    for prefix in prefixes:
        files = [
            os.path.join(base_path, f)
            for f in os.listdir(base_path)
            if f.endswith(".xlsx") and f.startswith(prefix)
        ]
        files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
        for old_file_path in files[keep_count:]:
            os.remove(old_file_path)
            print(f"Deleted old file: {old_file_path}")


def list_disks():
    ignore = {"user", "user0", "remotes", "rootshare", "addons"}
    entries = []
    for entry in os.listdir("/mnt"):
        path = os.path.join("/mnt", entry)
        if os.path.isdir(path) and entry not in ignore:
            entries.append(entry)
    return sorted(entries)


def should_skip(path):
    for keep in keep_paths:
        if path.startswith(keep):
            return False
    for pattern in skip_paths:
        if fnmatch.fnmatch(path, pattern):
            return True
    return False


def walk_disk_shares(disk_name):
    local_results = []
    for share_name in share_names:
        disk_path = os.path.join("/mnt", disk_name, share_name)
        if not os.path.exists(disk_path):
            continue
        for root, _, files in os.walk(disk_path):
            if should_skip(root):
                continue
            for file in files:
                local_results.append((file, disk_name, share_name, root))
    return local_results


def worker():
    while True:
        disk = disk_queue.get()
        if disk is None:
            break
        print(f"Processing {disk}")
        data = walk_disk_shares(disk)
        with lock:
            results.extend(data)
        disk_queue.task_done()


def format_excel(file_path, highlight_changes=False, white_text=True):
    wb = load_workbook(file_path)
    font_color = "FFFFFF" if white_text else "000000"
    data_font = Font(color=font_color)
    header_font = Font(color="FFFFFF", bold=True)
    red_fill = PatternFill(start_color="B22222", end_color="B22222", fill_type="solid")

    for sheet in wb.sheetnames:
        ws = wb[sheet]
        ws.freeze_panes = "A2"
        for row in ws.iter_rows():
            if row[0].row == 1:
                for cell in row:
                    if cell.value:
                        cell.value = str(cell.value).upper()
                    cell.font = header_font
                continue
            for cell in row:
                cell.font = data_font
            if highlight_changes and row[0].value == "REMOVED":
                for c in row:
                    c.fill = red_fill
        # Auto column width
        for col in ws.columns:
            max_len = 0
            col_letter = col[0].column_letter
            for cell in col:
                try:
                    if cell.value:
                        max_len = max(max_len, len(str(cell.value)))
                except:
                    pass
            ws.column_dimensions[col_letter].width = max_len + 2
    wb.save(file_path)


def save_results_to_excel(results, file_path):
    share_groups = defaultdict(list)
    for file_name, disk, share, path in results:
        share_groups[share].append((file_name, disk, path))
    for share in share_groups:
        share_groups[share].sort(key=lambda x: x[0].lower())
    with pd.ExcelWriter(file_path, engine="openpyxl") as writer:
        for share in share_names:
            if share not in share_groups:
                continue
            df = pd.DataFrame(share_groups[share], columns=["File Name", "Disk", "Path"])
            df.to_excel(writer, sheet_name=share[:31], index=False)


def compare_excels(file1, file2, output_file):
    print("Comparing files")
    df1 = pd.read_excel(file1, sheet_name=None)
    df2 = pd.read_excel(file2, sheet_name=None)
    differences = {}

    for sheet in set(df1.keys()).union(df2.keys()):
        df1_sheet = df1.get(sheet, pd.DataFrame())
        df2_sheet = df2.get(sheet, pd.DataFrame())
        df1_sheet = df1_sheet.fillna("").astype(str)
        df2_sheet = df2_sheet.fillna("").astype(str)

        # Only find removed rows
        removed = df1_sheet[~df1_sheet.apply(tuple, axis=1).isin(df2_sheet.apply(tuple, axis=1))]

        if not removed.empty:
            diffs = []
            for _, row in removed.iterrows():
                diffs.append(["REMOVED"] + list(row))
            differences[sheet] = pd.DataFrame(diffs, columns=["Change"] + list(df1_sheet.columns))

    # Always create the file
    with pd.ExcelWriter(output_file, engine="openpyxl") as writer:
        if differences:
            for sheet, df in differences.items():
                df.to_excel(writer, sheet_name=sheet[:31], index=False)
        else:
            pd.DataFrame(["No removed files"]).to_excel(writer, sheet_name="No Differences", index=False)

    format_excel(output_file, highlight_changes=True, white_text=False)
    print(f"Differences saved to {output_file}")


def main():
    cleanup_old_files()

    # Rotate old files
    if os.path.exists(old_file):
        os.remove(old_file)
        print(f"Removed {old_file}")
    if os.path.exists(diff_file):
        os.remove(diff_file)
        print(f"Removed {diff_file}")
    if os.path.exists(output_file):
        os.rename(output_file, old_file)
        print(f"Renamed {output_file} -> {old_file}")

    disks = list_disks()
    for d in disks:
        disk_queue.put(d)

    threads = []
    for _ in range(num_threads):
        t = threading.Thread(target=worker)
        t.start()
        threads.append(t)

    disk_queue.join()

    for _ in threads:
        disk_queue.put(None)
    for t in threads:
        t.join()

    save_results_to_excel(results, output_file)
    format_excel(output_file, white_text=True)

    if os.path.exists(old_file):
        compare_excels(old_file, output_file, diff_file)


if __name__ == "__main__":
    if sys.version_info < (3, 6):
        print("Error: Python 3.6 or newer is required")
        sys.exit(1)
    main()

```
