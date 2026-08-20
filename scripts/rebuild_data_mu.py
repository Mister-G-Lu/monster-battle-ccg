#!/usr/bin/env python3
"""Rebuild data.mu with fixed CSVs from csv_plain/."""
import zipfile, os, shutil

decoded_apk = 'build/decoded_apk'
data_mu_src = os.path.join(decoded_apk, 'assets', 'data.mu')
csv_dir = 'csv_plain'
temp_dir = 'build/data_mu_temp'

os.makedirs(temp_dir, exist_ok=True)

# Extract current data.mu
with zipfile.ZipFile(data_mu_src, 'r') as zin:
    entries = zin.namelist()
    print(f'Current data.mu has {len(entries)} entries')
    zin.extractall(temp_dir)

# Replace CSV files with fixed versions
replaced = 0
for entry in entries:
    if entry.endswith('.csv'):
        basename = os.path.basename(entry)
        src = os.path.join(csv_dir, basename)
        dst = os.path.join(temp_dir, entry)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            replaced += 1
            print(f'  Replaced: {basename}')

print(f'Replaced {replaced} CSV files')

# Create new data.mu
new_data_mu = 'build/data_new.mu'
with zipfile.ZipFile(new_data_mu, 'w', zipfile.ZIP_STORED) as zout:
    for root, dirs, files in os.walk(temp_dir):
        for f in files:
            full = os.path.join(root, f)
            arcname = os.path.relpath(full, temp_dir).replace(os.sep, '/')
            zout.write(full, arcname)

new_size = os.path.getsize(new_data_mu)
print(f'New data.mu: {new_size} bytes')

# Replace in decoded APK
shutil.copy2(new_data_mu, data_mu_src)
print('Updated decoded APK with new data.mu')

# Cleanup
shutil.rmtree(temp_dir, ignore_errors=True)
os.remove(new_data_mu)
print('Done!')
