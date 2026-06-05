# 家庭健康档案

Flutter 安卓应用，管理个人及家人/宠物的就诊记录、健康数据与用药提醒。

## 功能

### 核心

- **家庭成员管理** — 添加家人和宠物，为每个成员独立建档
- **就诊记录** — 记录每次就诊的医院、诊断、症状、药品、费用、检查结果等
- **附件管理** — 拍照/相册上传病历、发票、处方、检验报告，支持全屏预览
- **时间轴** — 按就诊时间展示记录，快速浏览健康历史
- **用药提醒** — 定时推送服药提醒，支持多时段（早/中/晚/睡前）
- **体重追踪** — 记录体重变化，图表展示趋势
- **年度回顾** — 按年份统计就诊次数、费用等数据
- **数据导出** — 导出 CSV 文件，支持分享到其他应用
- **暗色模式** — 跟随系统，支持 Material Design 3

### OCR 识别

- **本地 OCR** — 使用 Google ML Kit 中文文本识别，离线可用
- **AI 增强 OCR** — 接入 OpenAI 兼容 API（支持任何兼容服务），智能提取结构化医疗信息
- **视觉模型** — 支持 GPT-4o 等视觉模型直接分析文档图片
- **智能预处理** — 图像灰度化、对比度拉伸，提升识别精度
- **疾病词库** — 内置 200+ 常见疾病关键词匹配

### 通知

- 定时推送用药/复诊提醒
- 支持 Xiaomi/HyperOS 通知优化指南
- 完成/删除提醒自动取消通知
- 点击通知直接跳转提醒列表

## 环境要求

- Flutter SDK ≥ 3.2
- Android SDK (minSdk 24, targetSdk 34)
- Android 7.0+

## 运行

```bash
cd family_health_archive
flutter pub get
flutter run
```

构建 APK：

```bash
flutter build apk --debug   # 调试版
flutter build apk --release # 发布版
```

若目录缺少平台文件，可先执行：

```bash
flutter create . --project-name family_health_archive --org com.familyhealth
```

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x (Dart ≥ 3.2) |
| 状态管理 | Riverpod |
| 数据库 | sqflite (SQLite) |
| 路由 | go_router |
| 通知 | flutter_local_notifications |
| OCR | google_mlkit_text_recognition + AI API |
| 图表 | fl_chart |
| HTTP | http |
| 图像处理 | image (v4), flutter_image_compress |
| UI | Material Design 3，中文本地化，跟随系统深色模式 |

## 项目结构

```
lib/
  main.dart                          # 入口
  app.dart                           # MaterialApp 配置
  core/
    enums.dart                       # 枚举定义
    theme/app_theme.dart             # 主题配置
  data/
    database/app_database.dart       # SQLite 数据库（建表/迁移/CRUD）
    repositories/                    # 数据仓库层
      attachment_repository.dart
      medical_record_repository.dart
      person_repository.dart
      reminder_repository.dart
      tag_repository.dart
      weight_repository.dart
  providers/app_providers.dart       # Riverpod 全局 providers
  router/app_router.dart             # 路由定义
  screens/
    home/                            # 首页时间轴
    person/                          # 成员管理
    record/                          # 就诊记录（详情/编辑）
    reminder/                        # 提醒（列表/编辑）
    search/                          # 搜索
    settings/                        # 设置
    weight/                          # 体重追踪
    annual_review/                   # 年度回顾
    shell/                           # 底部导航壳
  services/
    ai_ocr_service.dart              # AI OCR 服务
    ocr_service.dart                 # 本地 OCR 服务
    notification_service.dart        # 通知服务
    avatar_service.dart              # 头像服务
    first_launch_service.dart        # 首次启动处理
    image_compress_service.dart      # 图片压缩
    widget_service.dart              # 桌面小组件
  widgets/                           # 通用组件
```

## AI OCR 配置

1. 打开设置 → AI OCR 设置
2. 填入 API Key 和 Endpoint（兼容 OpenAI 格式的 API 均可）
3. 选择文本模型（如 gpt-4o-mini）和视觉模型（如 gpt-4o）
4. 启用后，拍照识别时将自动调用 AI 提取结构化医疗信息

## Xiaomi/HyperOS 通知设置

小米手机用户若收不到定时提醒通知，请检查：

1. **设置 → 应用 → 家庭健康档案 → 通知** — 开启所有通知，打开「悬浮通知」
2. **设置 → 应用 → 家庭健康档案 → 自启动** — 开启自启动
3. **设置 → 应用 → 家庭健康档案 → 省电策略** — 选择「无限制」
4. App 内 **设置 → 小米权限设置** 可查看详细指引

## 数据库版本

当前版本 v4：

- v1 → v2：添加 tags 字段
- v2 → v3：添加 share_token、share_expiry 字段
- v3 → v4：添加 medicine 字段

## License

MIT
