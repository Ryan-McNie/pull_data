import os
from ftplib import FTP_TLS
import sys

# Command-line arguments: doy, year, prevdoy, prevyear, localdir
doy = sys.argv[1]
year = sys.argv[2]
prevdoy = sys.argv[3]
prevyear = sys.argv[4]
localdir = sys.argv[5]

ftp_server = "gdc.cddis.eosdis.nasa.gov"
ftp_user = "anonymous"
ftp_password = "rmcnie@linz.govt.nz"

# Connect to the FTP server via TLS
ftp = FTP_TLS(ftp_server)
ftp.login(user=ftp_user, passwd=ftp_password)
ftp.prot_p()  # Enable secure data connection

# Change directory on the FTP server
ftp.cwd(f"/gnss/data/daily/{year}/brdc/")
# print("Remote directory listing:", ftp.nlst())

# Define remote file paths
file1 = f"/gnss/data/daily/{year}/brdc/BRDC00IGS_R_{year}{doy}0000_01D_MN.rnx.gz"
file2 = f"/gnss/data/daily/{prevyear}/brdc/BRDC00IGS_R_{prevyear}{prevdoy}0000_01D_MN.rnx.gz"

# Create the local directory if it doesn't exist
if not os.path.exists(localdir):
    os.makedirs(localdir)

def download_file(remote_path):
    local_path = os.path.join(localdir, os.path.basename(remote_path))
    with open(local_path, "wb") as f:
        ftp.retrbinary("RETR " + remote_path, f.write)

# Download the two files
download_file(file1)
download_file(file2)

# Close the FTP connection
ftp.quit()


# ------------------------------
# Additional processing: extract, combine, and cleanup

import glob
import gzip
import shutil
import subprocess

def extract_gz_files(directory):
    """
    Extract all .gz files in the specified directory,
    and delete the original .gz files after extraction.
    """
    gz_files = glob.glob(os.path.join(directory, "*.gz"))
    for file_path in gz_files:
        out_file = file_path[:-3]  # Remove the '.gz' extension for the output file name.
        with gzip.open(file_path, "rb") as f_in, open(out_file, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        os.remove(file_path)

def run_gfzrnx(directory, year, doy):
    """
    Combine the navigation data using the gfzrnx tool.
    """
    input_pattern = os.path.join(directory, "BRDC*MN.rnx")
    output_file = os.path.join(directory, f"BRDC00IGS_R_{year}{doy}0000_01D_MN.RNX")
    cmd = f"gfzrnx -finp {input_pattern} -fout {output_file} -f"
    subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def remove_rnx_files(directory):
    """
    Remove all .rnx files in the directory.
    This is used to clean up the individual navigation files after combining them.
    """
    rnx_files = glob.glob(os.path.join(directory, "*.rnx"))
    for file_path in rnx_files:
        try:
            os.remove(file_path)
        except Exception as e:
            print(f"Error removing {file_path}: {e}")

# Execute the steps sequentially
extract_gz_files(localdir)
run_gfzrnx(localdir, year, doy)
remove_rnx_files(localdir)
