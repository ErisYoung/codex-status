# CodexStatus

macOS 菜单栏小工具：自动跟踪最新活动的 Codex 任务，实时显示 **空闲 / 思考中 / 完成 / 中断**，任务完成或中断时弹系统通知。

## 工作原理

- 只读监控 `~/.codex/sessions/**/*.jsonl`（Codex 桌面应用与 CLI 都会实时写入的会话记录）。
- 关键事件：`task_started`（任务开始）、`task_complete`（完成）、`turn_aborted`（中断）。
- 只跟踪 `thread_source` 为 `user` 的用户任务；桌面端内部的 guardian/审批子线程不会触发状态与通知。
- 应用图标：本地存在 `Assets/AppIcon-source.png`（ChatGPT 桌面应用自带的官方 Codex 图标，不入库）时使用它；否则由 `scripts/make_icon.swift` 生成一个「>_」占位图标。
- 不修改 Codex 配置、不需要额外系统权限、离线可用。

## 构建与安装

```bash
cd tools/codex-status
./scripts/build.sh      # 编译并生成图标
./scripts/install.sh    # 安装到 ~/Applications/CodexStatus.app
open "$HOME/Applications/CodexStatus.app"
```

## 测试

```bash
./scripts/test.sh        # 编译并运行单元测试（57 项断言）
```

> 本机 CommandLineTools 的 SDK 与 Swift 编译器版本不匹配（SDK 由 6.0.3.1.5 构建、编译器为 6.0.3.1.10），脚本检测到该错误会自动改用 MacOSX14.5.sdk 重试，无需手动处理。
> 请通过 `./scripts/build.sh` / `./scripts/test.sh` 构建；直接运行 `swift build` 会因测试运行器需要 `-enable-testing` 而失败。

## 菜单栏说明

- 状态文字：空闲 / 思考中 / 完成 / 中断 / 无活动（思考中超过 10 分钟没有新事件）。
- 菜单栏为「● 状态」样式：大号彩色圆点随状态着色（空闲灰 / 思考中蓝 / 完成绿 / 中断红 / 无活动橙），思考中圆点带呼吸闪烁，旁边显示状态文字。
- 完成或中断时发送系统通知（首次运行会请求通知权限；被拒绝时回退为提示音）。
- 可选「登录时启动」（需要 App 位于 `/Applications` 或 `~/Applications`）。

## 限制

- 跟踪范围是「最新活动的任务」；后台并行任务完成的通知可能在其成为最新活动时才会触发。
- 数据源是 Codex 会话记录文件，若 Codex 改变文件格式需相应适配。
