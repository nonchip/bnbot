require 'luarocks.loader'
require 'cutorch'
require 'cunn'
rnn = require 'rnn'
math = require 'math'
torch.setdefaulttensortype('torch.CudaTensor')

Api = require 'bnb_api'
Klines = require 'bnb_api.klines'

seqlen = 180
batchsize = 1
featsize = 3

hiddenSize = 100

net = if io.open(arg[1]..'.net','r')
  print 'loading net '..arg[1]..'.net'
  torch.load arg[1]..'.net'
else
  print 'creating new net'
  with nn.Sequential!
    \add nn.Sequencer nn.Linear featsize, hiddenSize
    \add nn.SeqLSTM hiddenSize, hiddenSize
    \add nn.SeqLSTM hiddenSize, hiddenSize
    \add nn.SeqLSTM hiddenSize, hiddenSize
    \add nn.Sequencer nn.Linear hiddenSize, featsize


net\cuda!

criterion = nn.SequencerCriterion nn.MSECriterion!, true
criterion\cuda!

api=Api!
api\do_cooldowns!
lines=Klines api, arg[1]
input = torch.Tensor seqlen, batchsize, featsize
input\zero!
input\cuda!
nullrow = torch.Tensor 1,batchsize,featsize
nullrow\zero!
nullrow\cuda!
local target
cdtime=torch.Timer!
savecounter=10
prevloss=-1
lossfile=io.open arg[1]..'.loss', 'r' unless arg[2] == '-lr'
updatestrength=if lossfile
  lossfile\seek 'set', -256
  text = lossfile\read '*a'
  r=tonumber string.match text, '[^;]*$'
  lossfile\close!
  r
else
 -1

lossfile=io.open arg[1]..'.loss', 'a'
lossstr=''
while true
  for line in lines\next
    break if #line.tbl==0
    print 'API line:',line.openTime, line.low, line.high, line.numberOfTrades
    newtens = torch.Tensor 1,batchsize,featsize
    newtens[1][1][1],newtens[1][1][2],newtens[1][1][3] = line.low, line.high, line.numberOfTrades
    input=torch.cat input\narrow(1,2,seqlen-2), newtens,1
    target = torch.cat nullrow, input\narrow(1,2,seqlen-2),1
  while not (api\mayRequest!)
    cdtime\reset!
    output = net\forward input
    loss = criterion\forward output, target
    grads = criterion\backward output, target
    net\zeroGradParameters!
    net\backward input, grads
    udir='='
    if updatestrength<0
      updatestrength = 1/loss
    if prevloss>=0
      if loss < prevloss
        updatestrength *=1.01
        udir='+'
      else
        updatestrength *=0.99
        udir='-'
    lossstr..= tostring(loss)..';'..tostring(updatestrength)..'\n'
    net\updateParameters updatestrength
    prevloss=loss
    print 'TRAINING loss:',loss, 'input:',input[seqlen-2][1][1], 'updated for:', updatestrength, udir
    api\cooldown cdtime\time!.real
  if prevloss>0 and prevloss < 50--input[seqlen-2][1][1]
    output = torch.cat nullrow,input\narrow(1,2,seqlen-2),1
    for i=1,5
      output = net\forward output
    print 'PREDICTION 5m:', unpack output[seqlen-1][1]
  savecounter-=1
  if savecounter == 0
    savecounter=10
    print 'saving net '..arg[1]..'.net and loss '..arg[1]..'.loss'
    torch.save arg[1]..'.net', net
    lossfile\write lossstr
    lossstr=''
    lossfile\flush!