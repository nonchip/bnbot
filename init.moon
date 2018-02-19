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

  seqlen = 180
  batchsize = 1
  featsize = 3

  hiddenSizes = {
    featsize*featsize
    featsize*featsize*featsize
    featsize*featsize*featsize*featsize
    featsize*featsize*featsize
    featsize*featsize
  }

  net,optimstate = if io.open(symbol..'.net','r')
    status 'loading net '..symbol..'.net'
    unpack torch.load symbol..'.net'
  else
    status 'creating new net'
    (with nn.Sequential!
      --\add nn.Sequencer nn.Linear featsize, hiddenSize
      \add nn.SeqLSTM featsize, hiddenSizes[1]
      for i=1,#hiddenSizes-1
        \add nn.SeqLSTM hiddenSizes[i], hiddenSizes[i+1]
      \add nn.Sequencer nn.Linear hiddenSizes[#hiddenSizes], featsize),{}


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

  dirarrow=(output,input,n,mul=0.01)->
    a=output[seqlen-1][1][n]
    b=input[seqlen-2][1][n]
    if a > b*(1+mul)
      '▲'
    elseif a < b*(1-mul)
      '▼'
    else
      ' '

  lastloss=-1
  lastploss=-1
  lossdir=' '
  plossdir=' '

  while true
    for line in lines\next
      break if #line.tbl==0
      stdscr\attron curses.A_REVERSE
      stdscr\mvaddstr 2, 0, 'API:'
      stdscr\attroff curses.A_REVERSE
      stdscr\mvaddstr 3, 2, 'OT:       '..tostring(line.openTime)..'             '
      stdscr\mvaddstr 4, 2, 'LOW:      '..string.format('%.10f',line.low)..'             '
      stdscr\mvaddstr 5, 2, 'HIGH:     '..string.format('%.10f',line.high)..'             '
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
      stdscr\mvaddstr 10, 5, string.format('%.10f',scale[1])..'            '
      stdscr\mvaddstr 11, 5, string.format('%.10f',scale[2])..'            '
      stdscr\mvaddstr 12, 5, string.format('%.10f',scale[3])..'            '
      stdscr\move 0,0
      stdscr\refresh!
      target = torch.cat nullrow, input\narrow(1,2,seqlen-2),1
    while not (api\mayRequest!)
      cdtime\reset!
      optim.adadelta(feval,optimx,optimstate)
      lossstr..= tostring(loss)..'\n'
      --print 'TRAINING loss:',loss, 'input:',input[seqlen-2][1][1]
      if lastloss>-1
        lossdir=if loss<lastloss
          '▼'
        else
          '▲'
      lastloss=loss
      stdscr\mvaddstr 3, 42, plossdir..lossdir..' LOSS: '..string.format('%.10f',loss)..'               '
      stdscr\mvaddstr 4, 42, 'LAST IN: '..string.format('%.10f',input[seqlen-2][1][1]/scale[1])..'               '
      stdscr\mvaddstr 7, 2, 'COOLDOWN: '..tostring(math.ceil(api.cooldown_t*100)/100)..'       '
      stdscr\move 0,0
      stdscr\refresh!
      api\cooldown cdtime\time!.real
    plossdir=' '
    if lastploss>-1
      plossdir=if loss<lastploss
        '▼'
      else
        '▲'
    lastploss=loss
    stdscr\mvaddstr 3, 42, plossdir..lossdir..' LOSS: '..string.format('%.10f',loss)..'               '
    output = torch.cat nullrow,input\narrow(1,2,seqlen-2),1
    ldir,hdir,tdir='','',''
    o2=output\clone!
    for i=1,5
      output = net\forward output
      ldir..=dirarrow(output,o2,1,0.005)
      hdir..=dirarrow(output,o2,2,0.005)
      tdir..=dirarrow(output/10,o2/10,3,0.005)
      o2=output\clone!
    cldir=dirarrow output,input,1
    chdir=dirarrow output,input,2
    ctdir=dirarrow output/10,input/10,3
    doscale output, false
    stdscr\attron curses.A_REVERSE if loss*scale[1] < input[seqlen-2][1][1]
    stdscr\mvaddstr 6, 40, 'PREDICTION:'
    stdscr\attroff curses.A_REVERSE
    lp=math.abs math.floor((output[seqlen-1][1][1]-input[seqlen-2][1][1]/scale[1])/(input[seqlen-2][1][1]/scale[1])*10000)/100
    hp=math.abs math.floor((output[seqlen-1][1][2]-input[seqlen-2][1][2]/scale[2])/(input[seqlen-2][1][2]/scale[2])*10000)/100
    stdscr\mvaddstr 7, 42, chdir..' LOW:     '..ldir..' '..string.format('%.10f',output[seqlen-1][1][1])..'  '..lp..'%               '
    stdscr\mvaddstr 8, 42, cldir..' HIGH:    '..hdir..' '..string.format('%.10f',output[seqlen-1][1][2])..'  '..hp..'%               '
    stdscr\mvaddstr 9, 42, ctdir..' #TRADES: '..tdir..' '..string.format('%.10f',output[seqlen-1][1][3])..'                 '
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