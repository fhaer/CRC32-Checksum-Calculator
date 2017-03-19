# CRC32-Checksum-Calculator
Calculates CRC32-checksums (for bit-rot-detection only) for specified directories recursively and compares values to the previous run. In the event of a mismatch, an e-mail is sent.

- directories are specified in %dir inside the script
- outputs values are written to an sfv-file for each directory
- in subsequent runs
  - a crc-value for each file is calculated again
  - IF file modification time has not changed, the value is compared to the one in the sfv file
  - IF a mismatch occurs, an e-mail is sent
  - new checksums are written to a new sfv file, the old file is backed up 

Usage: perl ccrc.pl

Requires: perl with libdigest-crc-perl
