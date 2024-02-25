## 介绍
记录在Ubuntu下使用git命令更新代码到github的过程


----------

## 在github上创建版本库
1. 在github上注册账号
2. 获取本机的ssh密钥
`$ ssh-keygen -C 'xxx' -t rsa`
其中`xxx`处为你的电子邮箱，可以和github的注册邮箱不一致。此命令会在`~/.ssh`文件夹下建立保存秘钥。如果`~/.ssh`已经有文件，则不用执行这一步。
3. 将ssh秘钥添加到github账户
进入你的github账户，点击右上角的`Edit profile`，再点击侧边栏的`SSH and GPG keys`，再点击右上角的`New SSh Key`，此时要求输入Title和Key，Title可以任意取，Key中需要填入刚才生成的秘钥，该秘钥的位置是`~/.ssh/id_rsa.pub`，将这个文件中的内容复制，并粘贴到Key中，然后点击`Add SSH Key`即可。
4. 创建新的版本库
需要在github上新建一个空的版本库，才能把本地版本库push到github上。
进入github账户，点击`Repositories`，再点击`New`，在`Repository name`处填上工程的名字，`Description`处填上描述，然后点击`Create repository`即可。
注意：为保证这个版本库是空的，我们不需要添加README.md或者LICENCE等文件。

----------

## 创建本地代码仓库
1. 安装git
`$ sudo apt-get install git`
2. 初始化git配置
`$ git config --global user.name "xxx"`: 你的git账户的用户名
`$ git config --global user.email xxx`: 你的git账户的邮箱
2. 在本地创建版本库
进入项目文件夹，运行命令：
`$ git init`
此时在当前文件夹下多出一个.git文件，这是一个空的代码仓库，并且位于本地。
3. 添加文件到版本库
`$ git add file`: 添加当前文件夹下的file文件到版本库。
`$ git add -A`: 添加当前文件夹下所有已经更改的文件或新文件到版本库。
注意，执行`git add`命令后，更改添加到缓存当中，还没有提交到本地的版本库，所以此时本地的版本库仍然是空的。
4. 提交更改到版本库
`$ git commit -m "xxx"`: 将当前的更改提交到版本库，"xxx"的内容为本次更改的简短说明。
`$ git status`: 查看已经提交的更改，已提交的更改为绿色，会被push命令推送到代码仓库，红色为未提交的更改。

----------

## 将本地代码推送到github
1. 添加github上的远程仓库
`$ git remote add xxx https://github.com/username/repository.git`
其中`xxx`为远程仓库的名字，可以任意取，一般取为`origin`
`https://github.com/username/repository.git`为刚才在github上新建的版本库的地址。
该命令就是连接github上的版本库，并取名为origin，以后对origin的操作就是对远程仓库的操作。
2. 推送代码到github
`$ git push origin master`
3. 后续操作
以后如果修改了本地代码只需执行：
`
$ git add -A
$ git commit -m "xxx"
$ git push origin master
`
即可推送到github

## 创建分支等操作
---------
查看分支：`git branch`

创建分支：`git branch <name>`

切换分支：`git checkout <name>`

创建+切换分支：`git checkout -b <name>

合并某分支到当前分支：git merge <name>`

删除分支：`git branch -d <name>`

## git pull 和本地文件冲突问题解决
--------
缓存起来: `git stash`  

分支: `git pull origin` 

还原: `git stash pop`

清理缓存: `git stash clear`

## .gitignore文件的使用
https://www.jianshu.com/p/a49124700abc