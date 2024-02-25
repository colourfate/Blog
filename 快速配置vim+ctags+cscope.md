## 介绍
配置vim是Linux环境下开发的日常，这里记录如何快捷地配置好vim+ctags+cscope开发环境。

## 安装必要软件
**插件管理器**
```bash
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
```
**ctags、cscope**
要使用这两个功能，除了要配置vim外，还有安装相应的软件。
```bash
$ sudo apt-get install ctags cscope
```

## 创建.vimrc文件
创建`~/.vimrc`文件，内容如下：
```
set paste
set encoding=utf-8
syntax on
set autoindent
set smartindent
set tabstop=4
set softtabstop=4
set expandtab
set ai!
set cindent shiftwidth=4
set number
set ruler
set laststatus=2
set statusline=%<%F\ [%l]
colorscheme desert
set mouse=a
set guifont=Mono\ 12
" 普通模式下，全选快捷键
nmap <C-a> ggvG$
" 选中状态下，Ctrl+c复制到+寄存器
vmap <C-c> "+y
" 普通模式下，Ctrl+v粘贴
nmap <C-v> p

" ----------------------------- Vundle -----------------------------
set nocompatible
filetype off
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'VundleVim/Vundle.vim'

call vundle#end()
filetype plugin indent on

" ----------------------------- Nerdtree -----------------------------
Plugin 'The-NERD-tree'
let NERDTreeIgnore=['\.pyc','\~$','\.swp','\.o','\.ko','\.symvers','\.order','\.mod.c']
map <F3> :NERDTreeToggle<CR> :Tlist<CR>
  
" ----------------------------- Taglist -----------------------------
Plugin 'taglist.vim'
let Tlist_Show_One_File=1     "不同时显示多个文件的tag，只显示当前文件的    
let Tlist_Exit_OnlyWindow=1   "如果taglist窗口是最后一个窗口，则退出vim   
let Tlist_Ctags_Cmd="/usr/bin/ctags" "将taglist与ctags关联
let Tlist_Use_Right_Window=1

" ----------------------------- Cscope -----------------------------
if has("cscope")
    set csprg=/usr/bin/cscope
    set csto=0
    set cst
    set nocsverb
    " add any database in current directory
    if filereadable("cscope.out")
    	cs add cscope.out
    " else add database pointed to by environment
    elseif $CSCOPE_DB != ""
        cs add $CSCOPE_DB
    endif
    set csverb
endif
nmap <C-\>s :cs find s <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>g :cs find g <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>c :cs find c <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>t :cs find t <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>e :cs find e <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>f :cs find f <C-R>=expand("<cfile>")<CR><CR>
nmap <C-\>i :cs find i ^<C-R>=expand("<cfile>")<CR>$<CR>
nmap <C-\>d :cs find d <C-R>=expand("<cword>")<CR><CR>
```
保存并退出，然后再次打开vim，输入`：PluginInstall`然后回车，等待插件管理器安装好插件。

## 生成tags和cscope.out数据库
执行以下命令：
```bash
$ ctags -R *
$ find ./ -name "*.c" -o -name "*.h" -o -name "*.s" -o -name "*.S" -o -name "*.dts" -o -name "*.dtsi" > cscope.files
$ cscope -bkq -i cscope.files
```
第一句递归当前目录，生成tags文件，第二句找到linux内核常用文件类型并写入cscope.files文件，第三句生成cscope.out数据库。

## 快捷键
`v`：进入visual模式，使用上下左右对文本进行框选
`v+d`：visual模式下按d，剪切文本，并回到normal模式
`v+y`：visual模式下按y，复制文本，并回到normal模式
`p`：粘贴
`yy`：复制一行
`Ctrl+o`：跳回上一个光标位置
`Ctrl+i`：跳到下一个光标位置

#### ctags
首先需要在根目录执行ctags -R创建tag文件，然后在根目录打开gvim
`Ctrl+]`：跳转到函数定义
`Ctrl+t`：返回

#### cscope
光标移动到要查找的文本处：
`Ctrl+\+s`：查找C语言符号，即查找函数名、宏、枚举值等出现的地方
`Ctrl+\+g`：查找函数、宏、枚举等定义的位置，类似ctags所提供的功能
`Ctrl+\+c`：查找本函数调用的函数
`Ctrl+\+t`：查找指定的字符串
`Ctrl+\+e`：查找egrep模式，相当于egrep功能
`Ctrl+\+f`：查找并打开文件，类似vim的find功能
`Ctrl+\+i`：查找包含本文件的文件

#### taglist
`F8`：打开taglist窗口，鼠标双击可跳转到相应函数定义
 `o` ：在一个新打开的窗口中显示光标下tag
 `<Space>`：显示光标下tag的原型定义
 `u`： 更新taglist窗口中的tag
 `s`：更改排序方式，在按名字排序和按出现顺序排序间切换
 `x`： taglist窗口放大和缩小，方便查看较长的tag
 `+`： 打开一个折叠，同zo
 `-`：将tag折叠起来，同zc
 `*`：打开所有的折叠，同zR
 `=`：将所有tag折叠起来，同zM
 `[[`：跳到前一个文件
 `]]`：跳到后一个文件
 `q`：关闭taglist窗口
 `<F1>`：显示帮助