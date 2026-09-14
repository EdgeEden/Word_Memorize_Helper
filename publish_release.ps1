# PowerShell 自动化发布 GitHub Release 脚本
$ErrorActionPreference = "Stop"

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$repo = "EdgeEden/Word_Memorize_Helper"
$tag = "v1.0.5"
$title = "v1.0.5: 单词发音与 Web 跨域发音优化"
$notes = "## 更新说明 (v1.0.5)`n`n1. 🔊 **新增单词读音与发音设置**：支持有道词典与 Free Dictionary 双音源，提供自动朗读模式配置与音标旁一键发音`n2. 🌐 **Web 端跨域发音驱动优化**：独立实现原生 HTML5 Audio 播放，彻底解决 WebAudio CORS 限制`n3. 🎯 **弹窗焦点管理与防误拉键盘**：彻底解决检查更新与弹窗交互时焦点被主界面抢占的问题`n4. 📱 **偏好设置高级选项 UI 布局优化**：针对移动端屏幕释放横向空间，排版更舒适`n`n## 📦 安装包下载`n- **Android APK**: WordN_Android_Release.apk`n- **Windows 便携包**: WordN_Windows_x64.zip"

$apkPath = "server/dist/WordN_Android_Release.apk#WordN_Android_Release.apk"
$zipPath = "server/dist/WordN_Windows_x64.zip#WordN_Windows_x64.zip"

Write-Host "正在发布 GitHub Release: $tag ..." -ForegroundColor Cyan
gh release create $tag $apkPath $zipPath --repo $repo --title $title --notes $notes

Write-Host "✅ 发布成功！查看地址: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
