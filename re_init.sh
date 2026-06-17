cd ~/sing-box/dist

# 彻底清除旧的 git 配置（如果之前有的话）
rm -rf .git

# 初始化（这会自动在当前目录下生成隐藏的 .git 文件夹）
git init

# 照常添加并提交文件
git add .
git commit -m "Initial commit for nanoswift custom sing-box"

# 关联并推送到你的 GitHub
git branch -M main
git remote add origin  git@github.com:is928joe-jpg/sing-box-with-nanoswift.git
git push -u origin main -f
