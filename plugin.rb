# name: discourse-postal
# about: Sends email via Postal HTTP API instead of SMTP
# version: 0.1
# authors: Senior Engineer
# url: https://github.com/your-repo/discourse-postal

enabled_site_setting :postal_enabled

after_initialize do
  require_relative 'lib/postal_sender'

  # 注册 Postal 发送器
  ActionMailer::Base.add_delivery_method :postal, PostalSender

  # 监听设置变化，动态切换发送方式
  # 如果插件启用，强制使用 postal；否则回退到 smtp
  DiscourseEvent.on(:site_setting_changed) do |name, old_val, new_val|
    if name == :postal_enabled
      if new_val == true
        ActionMailer::Base.delivery_method = :postal
      else
        ActionMailer::Base.delivery_method = :smtp
      end
    end
  end

  # 初始化时检查设置
  if SiteSetting.postal_enabled
    ActionMailer::Base.delivery_method = :postal
  end
end
