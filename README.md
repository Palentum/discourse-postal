# discourse-postal

一个 Discourse 插件，使用 [Postal](https://postalserver.io/) HTTP API 替代 SMTP 发送邮件。

## 功能特性

- 通过 Postal HTTP API 发送 Discourse 邮件，无需配置 SMTP
- 在管理后台热切换启用/禁用，**无需重启服务**
- 支持多部分邮件（HTML + 纯文本）、CC/BCC、Reply-To 及附件
- 配置缺失时立即抛出异常，由 Sidekiq 自动重试，不会静默丢信

## 安装

将本插件目录放置到 Discourse 根目录的 `plugins/` 下：

```bash
cd <discourse-root>/plugins
git clone https://github.com/your-repo/discourse-postal.git discourse-postal
```

然后重启 Discourse 服务使插件生效。

## 配置

在 Discourse 管理后台 **Settings → Plugins** 中找到以下三项配置：

| 设置项 | 说明 | 默认值 |
|---|---|---|
| `postal_enabled` | 是否启用 Postal 发信（关闭后回退到 SMTP） | `false` |
| `postal_endpoint` | Postal API 发信端点 URL | `https://your-postal-server.com/api/v1/send/message` |
| `postal_api_key` | Postal Server API Key | 空 |

配置示例：

```
postal_endpoint: https://postal.example.com/api/v1/send/message
postal_api_key:  your-server-api-key
postal_enabled:  true
```

> **注意**：`postal_endpoint` 和 `postal_api_key` 任一为空时，插件会拒绝发信并抛出异常，Sidekiq 将自动将邮件任务加入重试队列。

## 工作原理

1. **`plugin.rb`** 将 `PostalSender` 注册为 ActionMailer 的 `:postal` 发送方式，并监听 `site_setting_changed` 事件，在 `postal_enabled` 变化时动态切换 `ActionMailer::Base.delivery_method`，无需重启。
2. **`lib/postal_sender.rb`** 实现 `deliver!(mail)` 接口。每次发信时实时读取 `SiteSetting`（非缓存），支持配置热更改。通过 `Net::HTTP` 向 Postal API 发送 JSON 请求，连接超时 5s，读取超时 10s。

## 开发

本插件需在 Discourse 实例内运行。

```bash
# 启动 Discourse 开发服务器（在 discourse 根目录执行）
bin/ember-cli -u

# 运行本插件的全部测试
bundle exec rspec plugins/discourse-postal/

# 运行单个测试文件
bundle exec rspec plugins/discourse-postal/spec/path/to/spec.rb
```

## 许可证

MIT
