# 家庭健康档案

Flutter 安卓应用，管理个人及家人/宠物的就诊记录、健康数据与用药提醒。

## 环境要求

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 最新稳定版
- Android SDK（minSdk 24）

## 运行

```bash
cd family_health_archive
flutter pub get
flutter run
```

若目录缺少平台文件，可先执行：

```bash
flutter create . --project-name family_health_archive --org com.familyhealth
```

然后保留 `lib/` 中的业务代码。

设置 |

## 技术栈（第一阶段）

- **状态管理**：Riverpod
- **数据库**：sqflite（SQLite，schema 与 Drift 设计对齐，后续可迁移至 `drift` + `build_runner`）
- **路由**：go_router
- **UI**：Material Design 3，中文本地化，跟随系统深色模式

## 首次启动

自动创建「本人」档案与一条示例门诊记录，便于理解时间轴与编辑流程。

## 项目结构

```
lib/
  core/           # 枚举、主题
  data/           # 数据库、仓库
  providers/      # Riverpod
  screens/        # 页面
  services/       # 头像、首次启动
  widgets/        # 通用组件
```
