#!/usr/bin/python

import sys
import os
import glob
import zlib
import optparse
import struct
import binascii
import traceback
IO_BUFFER_SIZE = 4096

# This variable defines how deep you want the tool to
# scan subfolders to find clog files
recursive_level = 5
lastseq = 0
def DecompressFile(file, outfile):
    dec = zlib.decompressobj(-zlib.MAX_WBITS)
    fin = open(file, "rb")
    fout = open(outfile, "wb")
    buffer = fin.read(IO_BUFFER_SIZE)
    while buffer:
      decompressed = dec.decompress(buffer)
      buffer = fin.read(IO_BUFFER_SIZE)
      fout.write(decompressed)
    decompressed = dec.flush()
    fout.write(decompressed)
    fout.close()
    fin.close()
    print(outfile)

def processfolder(folder, recursive_level):
  if(recursive_level<=0):
    return
  filelist = glob.glob(folder + "/*.clog")
  for file in filelist:
    DecompressFile(file, os.path.splitext(file)[0] + '.log')
  subfolders = glob.glob(folder + "/*/")
  for folder in subfolders:
    processfolder(folder, recursive_level-1)

def process(arg):
  if(arg.endswith('.clog') and os.path.isfile(arg)):
    DecompressFile(arg, os.path.splitext(arg)[0] + '.log')
  elif(os.path.isdir(arg)):
    processfolder(arg, recursive_level)

# decompress_clog.py now accept folder or file as arugments
# scenario 1 several files:       python decompress_clog.py 1.clog 2.clog
# scenario 2 current folder:      python decompress_clog.py ./
# scenario 3 several subfolders:  python decompress_clog.py clogs 202101

def main():
  global lastseq
  args = sys.argv[1:]
  if len(args) >= 1:
    for arg in args:
        process(arg)
  else:
    filelist = glob.glob("*.clog")
    for filepath in filelist:
        lastseq = 0
        process(filepath)

if __name__ == "__main__":
  main()
