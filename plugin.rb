# name: discourse-postal-mailer
# about: 使用 Postal HTTP API 发送邮件的 Discourse 插件
# version: 1.0.0
# authors: Your Name
# url: https://github.com/yourusername/discourse-postal-mailer

enabled_site_setting :postal_mailer_enabled

after_initialize do
  require 'net/http'
  require 'uri'
  require 'json'

  module ::PostalMailer
    class Client
      def initialize
        @api_url = SiteSetting.postal_api_url
        @api_key = SiteSetting.postal_api_key
        @from_address = SiteSetting.postal_from_address
      end

      def send_mail(to:, subject:, body:, html_body: nil, from: nil, reply_to: nil, cc: nil, bcc: nil)
        uri = URI.parse("#{@api_url}/api/v1/send/message")
        
        payload = {
          to: Array(to),
          from: from || @from_address,
          subject: subject,
          plain_body: body
        }

        payload[:html_body] = html_body if html_body
        payload[:reply_to] = reply_to if reply_to
        payload[:cc] = Array(cc) if cc
        payload[:bcc] = Array(bcc) if bcc

        request = Net::HTTP::Post.new(uri)
        request['X-Server-API-Key'] = @api_key
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        if response.code.to_i >= 200 && response.code.to_i < 300
          JSON.parse(response.body)
        else
          Rails.logger.error("Postal API Error: #{response.code} - #{response.body}")
          raise "Failed to send email via Postal: #{response.body}"
        end
      end
    end

    class Delivery
      def initialize(mail)
        @mail = mail
        @client = Client.new
      end

      def deliver!
        to = extract_addresses(@mail.to)
        from = extract_addresses(@mail.from).first
        subject = @mail.subject
        
        # 获取邮件正文
        plain_body = nil
        html_body = nil

        if @mail.multipart?
          @mail.parts.each do |part|
            if part.content_type =~ /text\/plain/
              plain_body = part.body.decoded
            elsif part.content_type =~ /text\/html/
              html_body = part.body.decoded
            end
          end
        else
          if @mail.content_type =~ /text\/html/
            html_body = @mail.body.decoded
            plain_body = strip_html(html_body)
          else
            plain_body = @mail.body.decoded
          end
        end

        # 发送邮件
        @client.send_mail(
          to: to,
          from: from,
          subject: subject,
          body: plain_body,
          html_body: html_body,
          reply_to: extract_addresses(@mail.reply_to).first,
          cc: extract_addresses(@mail.cc),
          bcc: extract_addresses(@mail.bcc)
        )
      end

      private

      def extract_addresses(addresses)
        return [] if addresses.nil?
        Array(addresses).map(&:to_s)
      end

      def strip_html(html)
        html.gsub(/<[^>]*>/, '').strip
      end
    end
  end

  # 注册邮件发送器
  ActionMailer::Base.add_delivery_method :postal, PostalMailer::Delivery

  # 配置 Discourse 使用 Postal
  if SiteSetting.postal_mailer_enabled
    ActionMailer::Base.delivery_method = :postal
    Rails.logger.info("Postal Mailer: Enabled and configured")
  end
end