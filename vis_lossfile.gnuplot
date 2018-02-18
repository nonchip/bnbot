set datafile separator ';'
set logscale y
plot 'TRXETH.loss' using ($0):1 title 'Loss' with lines
pause 5
reread
