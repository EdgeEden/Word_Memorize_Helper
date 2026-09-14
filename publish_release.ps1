# PowerShell 自动化发布 GitHub Release 脚本
$ErrorActionPreference = "Stop"

# 设置控制台与输入输出编码为 UTF-8，防止中文与 Emoji 乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$repo = "EdgeEden/Word_Memorize_Helper"
$tag = "v1.0.5"
$title = "v1.0.5: 单词发音与 Web 跨域发音优化"
$notesFile = Join-Path $PSScriptRoot "RELEASE_NOTES.md"

$apkPath = "server/dist/WordN_Android_Release.apk#WordN_Android_Release.apk"
$zipPath = "server/dist/WordN_Windows_x64.zip#WordN_Windows_x64.zip"

Write-Host "正在发布 / 更新 GitHub Release: $tag ..." -ForegroundColor Cyan
gh release create $tag $apkPath $zipPath --repo $repo --title $title --notes-file $notesFile

Write-Host "✅ 发布成功！查看地址: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
