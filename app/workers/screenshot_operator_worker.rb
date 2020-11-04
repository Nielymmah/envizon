class ScreenshotOperatorWorker
  include Sidekiq::Worker

  # do not use the background que!!.
  # This is a Worker to manage secondary Workers.
  # if both use the the same que, this can plug them.
  sidekiq_options queue: 'default' # !

  def perform(args)
    ActiveRecord::Base.connection_pool.with_connection do
      if args.include? "clients"
        ports = Port.all.where(client: args['clients']).select(&:screenshotable?)
      else
        ports = Port.all.select(&:screenshotable?)
      end
      # if overwrite=false -> select only ports without image.
      ports = ports.reject { |p| p.image.attached? } unless args['overwrite']
      ports.each do |port|
        begin
          ScreenshotWorker.perform_async({ 'port_id' => port.id })
        rescue StandardError => e
          logger.warn "Exception in ScreenshotOperatorWorker: #{e.message}"
        end
      end
      # ScreenshotWorker.wait_until_finish
      ActionCable.server.broadcast 'notification_channel', message: 'Screenshot-Job finished'
    end
  end
end
