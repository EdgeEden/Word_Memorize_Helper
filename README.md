# WordN (Word Memorize Helper) 智能背单词助手

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)
![Algorithm](https://img.shields.io/badge/FSRS-4.5-orange)
![AI](https://img.shields.io/badge/DeepSeek-AI-blue)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Version](https://img.shields.io/badge/Release-v1.0.5-brightgreen)

**基于 FSRS-4.5 算法与 DeepSeek 大语言模型语义判卷的跨平台现代化智能背单词助手**

[下载体验](#-下载与安装) • [核心特性](#-核心特性) • [技术架构](#-技术架构) • [快速上手](#-快速上手) • [开源协议](#-开源协议)

</div>

---

## ✨ 核心特性

- 🧠 **FSRS-4.5 科学记忆调度**：内置先进的 Free Spaced Repetition Scheduler 记忆曲线模型，比传统艾宾浩斯与 SM-2 算法更精准地预测记忆保留率，自适应动态调节复习间隔。
- 🤖 **DeepSeek AI 语义智能判卷**：支持接入 DeepSeek API，打破死板的字面匹配限制。支持中英文双向拼写容错、同义词语义理解与即时 AI 考点解析。
- 🔊 **多音源发音与自动朗读**：集成有道词典与 Free Dictionary API 双音源，支持英音/美音切换，以及切题自动朗读与音标旁一键发音。
- 📚 **自定义词库导入与管理**：支持标准 CSV 格式词库的多端一键导入与解析，支持多词库独立隔离管理与错题本自动收录。
- 🔄 **自建多端云同步服务**：伴生高性能 FastAPI 服务端，全平台（Android / Windows / Web）进度与词库秒级双向增量同步。
- 📱 **多端原生级体验**：
  - **Android**：原生 `DownloadManager` 后台下载更新，通知栏与应用内进度实时同步。
  - **Windows**：桌面端宽屏响应式布局，支持快捷键高效刷词。
  - **Web**：原生 HTML5 Audio 驱动，解决跨域限制与多端无缝使用。
- 📊 **学习看板与 Token 统计**：可视化每日复习曲线、记忆留存率统计，内置 AI Token 使用量与成本实时看板。

---

## 📥 下载与安装

请前往 [GitHub Releases](https://github.com/EdgeEden/Word_Memorize_Helper/releases/latest) 下载最新发行版：

| 平台 | 安装包格式 | 说明 |
| :--- | :--- | :--- |
| **Android** | `WordN_Android_Release.apk` | 适用于 Android 7.0+ 设备，支持应用内检测与后台下载更新 |
| **Windows** | `WordN_Windows_x64.zip` | 解压即可运行（无需安装），绿色便携 |
| **Web / 自建服务端** | 源码部署 | 支持 Docker 一键容器化部署 |

---

## 🛠️ 技术架构

```
WordN/
├── lib/                     # Flutter 客户端源码
│   ├── models/              # 数据模型（FSRS 状态卡片、词库、更新与统计）
│   ├── controllers/         # 业务逻辑控制器（答题流控、发音管理、状态流转）
│   ├── services/            # 核心服务（FSRS 算法、DeepSeek AI、音视频、云端同步、更新管理）
│   ├── screens/             # 页面视图（主学习界面、测验界面、统计看板）
│   └── widgets/             # 通用组件（登录弹窗、设置面板、自定义词库导入、AI 判定条）
├── server/                  # FastAPI 伴生同步服务端
│   ├── main.py              # 服务端接口路由（同步、版本检测、静态资源托管）
│   ├── database.py          # SQLite 数据库操作
│   ├── models.py            # 数据契约
│   └── Dockerfile           # 容器化构建配置
└── test/                    # 完整单元测试套件
```

---

## 🚀 快速上手

### 1. 客户端开发与构建

#### 环境要求
- Flutter SDK `>= 3.13.1`
- Dart SDK `>= 3.1.0`

```bash
# 克隆仓库
git clone git@github.com:EdgeEden/Word_Memorize_Helper.git
cd Word_Memorize_Helper

# 安装依赖
flutter pub get

# 运行单元测试
flutter test

# 启动客户端
flutter run

# 打包 Android APK
flutter build apk --release

# 打包 Windows 应用
flutter build windows --release
```

### 2. 伴生服务端部署（可选）

如需使用多端数据同步功能，可自行部署轻量级同步服务端：

#### 本地 / Python 运行
```bash
cd server
pip install -r requirements.txt
python main.py
```
服务端默认监听 `0.0.0.0:25642`。

#### Docker 一键部署
```bash
cd server
docker build -t wordn-server .
docker run -d -p 25642:25642 -v wordn_data:/app/data --name wordn-server wordn-server
```

在客户端登录设置中填入服务端地址（例如 `http://your-server-ip:25642`），即可实现多端数据自动同步。

---

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源协议。
