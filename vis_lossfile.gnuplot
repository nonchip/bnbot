set datafile separator ';'
set logscale y
set y2tics
plot 'TRXETH.loss' using ($0):1 title 'Loss' with lines, 'TRXETH.loss' using ($0):2 title 'Rate' with lines axes x1y2
pause 5
reread
