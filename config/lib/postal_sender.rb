require 'net/http'
require 'uri'
require 'json'

class PostalSender
  def initialize(values)
    @settings = values
  end

  def deliver!(mail)
    # 检查是否启用了插件
    return unless SiteSetting.postal_enabled

    endpoint = SiteSetting.postal_endpoint
    api_key = SiteSetting.postal_api_key

    if endpoint.blank? || api_key.blank?
      Rails.logger.error("Postal Plugin: Endpoint or API Key is missing.")
      raise "Postal configuration missing"
    end

    # 构建 Postal 需要的数据载荷
    payload = {
      to: mail.to,
      from: mail[:from].to_s,
      subject: mail.subject,
      headers: {
        "Message-ID" => mail.message_id,
        "In-Reply-To" => mail.in_reply_to,
        "References" => mail.references
      }
    }

    # 处理 CC 和 BCC
    payload[:cc] = mail.cc if mail.cc.present?
    payload[:bcc] = mail.bcc if mail.bcc.present?
    
    # 处理 Reply-To
    payload[:reply_to] = mail.reply_to.first if mail.reply_to.present?

    # 提取邮件正文 (处理 Multipart)
    if mail.multipart?
      payload[:plain_body] = mail.text_part ? mail.text_part.body.decoded : nil
      payload[:html_body] = mail.html_part ? mail.html_part.body.decoded : nil
    else
      # 如果不是 multipart，通常 discourse 发送的是 html 或 text
      if mail.content_type =~ /text\/html/
        payload[:html_body] = mail.body.decoded
      else
        payload[:plain_body] = mail.body.decoded
      end
    end

    # 处理附件 (如果有)
    if mail.attachments.present?
      payload[:attachments] = mail.attachments.map do |a|
        {
          name: a.filename,
          content_type: a.content_type,
          data: Base64.encode64(a.body.decoded)
        }
      end
    end

    # 发送 HTTP 请求
    send_request(endpoint, api_key, payload)
  end

  private

  def send_request(url, key, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    
    # 设置超时，防止阻塞 Discourse 队列太久
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request['X-Server-API-Key'] = key
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = http.request(request)

    # 简单的错误处理
    unless response.code.to_i >= 200 && response.code.to_i < 300
      error_msg = "Postal API Error: #{response.code} - #{response.body}"
      Rails.logger.error(error_msg)
      # 抛出异常以便 Sidekiq 可以重试
      raise error_msg
    end
    
    Rails.logger.info("Postal Plugin: Email sent successfully to #{payload[:to]}")
  end
end
