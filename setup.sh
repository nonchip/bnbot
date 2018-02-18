#!/bin/bash

export BNBOT_PATH="$(dirname $(readlink -f $0))"
export BNBOT_REAL_ROOT="$BNBOT_PATH/.root"
export BNBOT_SRC="$BNBOT_PATH/.src"
export BNBOT_ROOT="/tmp/.bnbot.$(uuidgen -t)-$(uuidgen -r)"

continue_stage=n
if [ -f "$BNBOT_PATH/.continue_stage" ]
  then continue_stage=$(cat "$BNBOT_PATH/.continue_stage")
fi

if [ -f "$BNBOT_PATH/.continue_root" ]
  then BNBOT_ROOT=$(cat "$BNBOT_PATH/.continue_root")
fi

export PATH="$BNBOT_PATH/tools:$BNBOT_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$BNBOT_ROOT/lib:$LD_LIBRARY_PATH"

case $continue_stage in
  n)
    rm -f "$BNBOT_PATH/.continue_stage"
    rm -rf "$BNBOT_ROOT" "$BNBOT_SRC" "$BNBOT_REAL_ROOT"
    mkdir -p "$BNBOT_REAL_ROOT" "$BNBOT_SRC"
    ln -s "$BNBOT_REAL_ROOT" "$BNBOT_ROOT"
    echo "$BNBOT_ROOT" > "$BNBOT_PATH/.continue_root"
    ;&
  submodules)
    echo "submodules" > "$BNBOT_PATH/.continue_stage"
    git submodule deinit --force --all
    git submodule update --init --force || exit
    ;&
  luajit) v=0bf80b07b0672ce874feedcc777afe1b791ccb5a
    echo "luajit" > "$BNBOT_PATH/.continue_stage"
    cd $BNBOT_SRC
    git clone http://luajit.org/git/luajit-2.0.git luajit || exit
    cd luajit
    git checkout ${v}
    make amalg PREFIX=$BNBOT_ROOT CPATH=$BNBOT_ROOT/include LIBRARY_PATH=$BNBOT_ROOT/lib CFLAGS='-DLUAJIT_ENABLE_LUA52COMPAT -DLUAJIT_ENABLE_GC64' && \
    make install PREFIX=$BNBOT_ROOT || exit
    ln -sf $(find $BNBOT_ROOT/bin/ -name "luajit-2.0*" | head -n 1) $BNBOT_ROOT/bin/luajit
    ln -sf $BNBOT_ROOT/lib/libluajit-5.1.so $BNBOT_ROOT/lib/lua/5.1/libluajit.so
    ;&
  luarocks) v=d2718bf39dace0af009b9484fc6019b276906023
    echo "luarocks" > "$BNBOT_PATH/.continue_stage"
    cd $BNBOT_SRC
    git clone https://github.com/luarocks/luarocks.git || exit
    cd luarocks
    git checkout ${v}
    git pull
    ./configure --prefix=$BNBOT_ROOT \
                --lua-version=5.1 \
                --lua-suffix=jit \
                --with-lua=$BNBOT_ROOT \
                --with-lua-include=$BNBOT_ROOT/include/luajit-2.0 \
                --with-lua-lib=$BNBOT_ROOT/lib/lua/5.1 \
                --force-config && \
    make build && make install || exit
    ;&
  moonscript)
    echo "moonscript" > "$BNBOT_PATH/.continue_stage"
    $BNBOT_ROOT/bin/luarocks install moonscript || exit
    ;&
  curses)
    echo "curses" > "$BNBOT_PATH/.continue_stage"
    $BNBOT_ROOT/bin/luarocks install lcurses || exit
    ;&
  websocket)
    echo "websocket" > "$BNBOT_PATH/.continue_stage"
    $BNBOT_ROOT/bin/luarocks install lua-websockets || exit
    ;&
  luasec)
    echo "luasec" > "$BNBOT_PATH/.continue_stage"
    $BNBOT_ROOT/bin/luarocks install luasec || exit
    ;&
  torch_modules)
    echo "torch_modules" > "$BNBOT_PATH/.continue_stage"
    for i in 'sundown' 'cwrap' 'paths' 'torch' 'nn' 'dok' 'gnuplot' 'cutorch' 'cunn' 'qtlua' 'qttorch' 'luafilesystem' 'penlight' 'sys' 'xlua' 'image' 'optim' 'lua-cjson' 'trepl' 'rnn'
      do if $BNBOT_ROOT/bin/luarocks list --porcelain | cut -f 1 | grep -q $i
        then echo "skipping $i"
      else
        $BNBOT_ROOT/bin/luarocks --server=https://raw.github.com/torch/rocks/master install $i || exit
      fi
    done
    ;&

  wrappers)
    echo "wrappers" > "$BNBOT_PATH/.continue_stage"
    # wrappers
    cat > "$BNBOT_PATH/.run" <<END
#!/bin/bash
export BNBOT_PATH="\$(dirname "\$(readlink -f "\$0")")"
export BNBOT_REAL_ROOT="\$BNBOT_PATH/.root"
export BNBOT_ROOT="$BNBOT_ROOT"

[ -e "\$BNBOT_ROOT" ] || ln -s "\$BNBOT_PATH/.root" \$BNBOT_ROOT

export PATH="\$BNBOT_PATH/tools:\$BNBOT_ROOT/bin:\$PATH"
export LD_LIBRARY_PATH="\$BNBOT_ROOT/lib:\$LD_LIBRARY_PATH"

path_prefixes=(./custom_ \$BNBOT_PATH/custom_ ./ \$BNBOT_PATH/ \$BNBOT_PATH/modules/ \$BNBOT_ROOT/lualib/ \$BNBOT_ROOT/share/luajit-2.0.5/ \$BNBOT_ROOT/share/lua/5.1/)

LUA_PATH=""
LUA_CPATH=""
MOON_PATH=""

for prefix in "\${path_prefixes[@]}"
  do LUA_PATH="\$LUA_PATH;\${prefix}?.lua;\${prefix}?/init.lua"
  LUA_CPATH="\$LUA_CPATH;\${prefix}?.so;"
  MOON_PATH="\$MOON_PATH;\${prefix}?.moon;\${prefix}?/init.moon"
done

export LUA_PATH
export LUA_CPATH
export MOON_PATH

fn="\$(basename "\$0")"
if [ "\$fn" = ".run" ]
  then exec "\$@"
else
  exec "\$fn" "\$@"
fi
END
    ln -s $BNBOT_PATH/.run $BNBOT_PATH/th
    ln -s $BNBOT_PATH/.run $BNBOT_PATH/bnbot
    chmod a+rx $BNBOT_PATH/.run $BNBOT_PATH/th $BNBOT_PATH/bnbot
    ;&
  moonc_all)
    echo "moonc_all" > "$BNBOT_PATH/.continue_stage"
    $BNBOT_PATH/.run moonc $BNBOT_PATH || exit
    ;&
esac

# cleanup
rm -rf "$BNBOT_SRC"
rm -f "$BNBOT_ROOT" "$BNBOT_PATH/.continue_stage" "$BNBOT_PATH/.continue_root"