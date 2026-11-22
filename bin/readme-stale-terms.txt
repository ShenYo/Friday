# Terms that must not appear in EITHER language version.
#
# A term lands here after it has been wrong once. The managed core grew from
# eleven files to fourteen (d785746) and the lists were updated but three
# sentences were not, in both languages; it has since grown to seventeen, and
# the fourteen-file wording is as stale as the eleven-file was.
#
# Checked against every file, not one term per file. A match is a plain
# substring, so the -檔 terms carry enough context not to sit inside a longer
# number (十一檔 is inside 二十一檔). The 十一個 / 十四個 managed-core terms
# would also match 二十一個 / 二十四個; such a match fails the check loudly.
eleven-file
eleven managed-core
的十一檔
著十一檔
十一個 managed-core
fourteen-file
fourteen managed-core
的十四檔
core 十四檔
十四個 managed-core
