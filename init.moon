require 'luarocks.loader'
require 'cutorch'
require 'cunn'
require 'optim'
rnn = require 'rnn'
math = require 'math'
curses = require 'curses'
torch.setdefaulttensortype('torch.CudaTensor')

Api = require 'bnb_api'
Klines = require 'bnb_api.klines'

symbol=arg[1]

main=->
  stdscr = curses.initscr!
  stdscr\clear!

  status=(arg)->
    stdscr\mvaddstr 0, 1, symbol..'   '..arg..'                                                                 '
    stdscr\move 0,0
    stdscr\refresh!

  seqlen = 60
  batchsize = 1
  featsize = 3

  hiddenSize = 100

  net,optimstate = if io.open(symbol..'.net','r')
    status 'loading net '..symbol..'.net'
    unpack torch.load symbol..'.net'
  else
    status 'creating new net'
    (with nn.Sequential!
      --\add nn.Sequencer nn.Linear featsize, hiddenSize
      \add nn.SeqLSTM featsize, hiddenSize
      \add nn.SeqLSTM hiddenSize, hiddenSize
      \add nn.SeqLSTM hiddenSize, hiddenSize
      \add nn.Sequencer nn.Linear hiddenSize, featsize),{}


  net\cuda!

  criterion = nn.SequencerCriterion nn.MSECriterion!, true
  criterion\cuda!

  api=Api!
  api\do_cooldowns!
  lines=Klines api, symbol
  input = torch.Tensor seqlen, batchsize, featsize
  input\zero!
  input\cuda!
  nullrow = torch.Tensor 1,batchsize,featsize
  nullrow\zero!
  nullrow\cuda!
  local target, loss
  cdtime=torch.Timer!
  savecounter=5
  lossfile=io.open symbol..'.loss', 'a'
  lossstr=''

  optimx,dldx = net\getParameters!
  feval = (x_new)->
    optimx\copy x_new unless optimx==x_new
    dldx\zero!
    output = net\forward input
    loss = criterion\forward output, target
    grads = criterion\backward output, target
    net\zeroGradParameters!
    net\backward input, grads
    loss, dldx

  status 'Running...'
  stdscr\mvaddstr 2, 40, 'TRAINING:'
  stdscr\mvaddstr 6, 40, 'PREDICTION:'
  stdscr\mvaddstr 2, 0, 'API:'
  stdscr\mvaddstr 9, 1,  'SCALE:'
  curses.echo false

  scale=torch.Tensor featsize
  scale\fill 1

  doscale=(inp,mul=true)->
    s=scale\clone!
    if not mul
      s\cinv!
    for i=1,featsize
      inp\select(3, i)\mul tonumber s[i]

  while true
    for line in lines\next
      break if #line.tbl==0
      stdscr\attron curses.A_REVERSE
      stdscr\mvaddstr 2, 0, 'API:'
      stdscr\attroff curses.A_REVERSE
      stdscr\mvaddstr 3, 2, 'OT:       '..tostring(line.openTime)..'             '
      stdscr\mvaddstr 4, 2, 'LOW:      '..tostring(line.low)..'             '
      stdscr\mvaddstr 5, 2, 'HIGH:     '..tostring(line.high)..'             '
      stdscr\mvaddstr 6, 2, '#TRADES:  '..tostring(line.numberOfTrades)..'             '
      stdscr\mvaddstr 7, 2, 'COOLDOWN: '..tostring(math.ceil(api.cooldown_t*100)/100)..'       '
      --print 'API line:',line.openTime, line.low, line.high, line.numberOfTrades
      newtens = torch.Tensor 1,batchsize,featsize
      newtens[1][1][1],newtens[1][1][2],newtens[1][1][3] = line.low, line.high, line.numberOfTrades
      doscale input, false
      input=torch.cat input\narrow(1,2,seqlen-2), newtens,1
      for i=1,featsize
        scale[i]=input\select(3,i)\max!
      scale\cinv!
      doscale input, true
      stdscr\mvaddstr 10, 5, tostring(scale[1])..'       '
      stdscr\mvaddstr 11, 5, tostring(scale[2])..'       '
      stdscr\mvaddstr 12, 5, tostring(scale[3])..'       '
      stdscr\move 0,0
      stdscr\refresh!
      target = torch.cat nullrow, input\narrow(1,2,seqlen-2),1
    while not (api\mayRequest!)
      cdtime\reset!
      optim.adadelta(feval,optimx,optimstate)
      lossstr..= tostring(loss)..'\n'
      --print 'TRAINING loss:',loss, 'input:',input[seqlen-2][1][1]
      stdscr\mvaddstr 3, 42, 'LOSS:    '..tostring(loss)..'               '
      stdscr\mvaddstr 4, 42, 'LAST IN: '..tostring(input[seqlen-2][1][1]/scale[1])..'               '
      stdscr\mvaddstr 7, 2, 'COOLDOWN: '..tostring(math.ceil(api.cooldown_t*100)/100)..'       '
      stdscr\move 0,0
      stdscr\refresh!
      api\cooldown cdtime\time!.real
    --if loss < input[seqlen-2][1][1]
    output = torch.cat nullrow,input\narrow(1,2,seqlen-2),1
    for i=1,5
      output = net\forward output
    --print 'PREDICTION 5m:', unpack output[seqlen-1][1]
    doscale output, false
    stdscr\attron curses.A_REVERSE if loss*scale[1] < input[seqlen-2][1][1]
    stdscr\mvaddstr 6, 40, 'PREDICTION:'
    stdscr\attroff curses.A_REVERSE
    stdscr\mvaddstr 7, 42, 'LOW: '..tostring(output[seqlen-1][1][1])..'               '
    stdscr\mvaddstr 8, 42, 'HIGH: '..tostring(output[seqlen-1][1][2])..'               '
    stdscr\mvaddstr 9, 42, '#TRADES: '..tostring(output[seqlen-1][1][3])..'               '
    stdscr\mvaddstr 2, 0, 'API:'
    stdscr\move 0,0
    stdscr\refresh!
    savecounter-=1
    if savecounter == 0
      savecounter=5
      status 'saving net '..symbol..'.net and loss '..symbol..'.loss'
      torch.save symbol..'.net', {net,optimstate}
      lossfile\write lossstr
      lossstr=''
      lossfile\flush!
    status 'Running, save in '..tostring(savecounter)

  curses.endwin!

err= (e)->
  curses.endwin!
  print "Caught an error:"
  print debug.traceback e, 2
  os.exit 2

xpcall main, err