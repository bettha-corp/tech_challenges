# -*- coding: utf-8 -*-
require 'active_record'
require 'sinatra'
require 'logger'
require 'rufus-scheduler'
require 'xlsx_writer'
require 'fileutils'
require 'yaml'

def main
  greetings

  puts 'Pressione Ctrl+C para sair'

  configure_app

  interval_minutes = @config['scheduler']['IntervalInMinutes'].to_i
  logger.warn("Intervalo entre as execuções do processo: #{interval_minutes}")

  scheduler = Rufus::Scheduler.new

  scheduler.every "#{interval_minutes}m", first_at: Time.now do
    task1
  end

  begin
    scheduler.join
  rescue Interrupt
    puts "\nScheduler interrompido."
  end
end

def greetings
  puts '             ##########################'
  puts '             # - ACME - Tasks Robot - #'
  puts '             # - v 1.0 - 2024-12-09 - #'
  puts '             ##########################'
end

def configure_app
  @logger = Logger.new('bot.log', 10, 10_000)
  @logger.level = Logger::INFO

  db_config = YAML.load_file('/tmp/bot/settings/database.yml')
  ActiveRecord::Base.establish_connection(db_config)

  @config = YAML.load_file('/tmp/bot/settings/config.yml')
end

def task1
  file_name = "data_export_#{Time.now.strftime('%Y%m%d%H%M%S')}.xlsx"
  file_path = File.join(Dir.pwd, file_name)
  workbook = XlsxWriter::Workbook.new(file_path)
  worksheet = workbook.add_worksheet

  orders = ActiveRecord::Base.connection.execute('SELECT * FROM users')

  index = 1
  headers = ['Id', 'Name', 'Email', 'Password', 'Role Id', 'Created At', 'Updated At']
  headers.each_with_index { |header, col| worksheet.write(index - 1, col, header) }

  orders.each do |order|
    index += 1
    order.each_with_index do |value, col|
      worksheet.write(index - 1, col, value)
    end
  end

  workbook.close
  puts 'Tarefa executada!'
rescue StandardError => e
  @logger.error("Erro ao executar a tarefa: #{e.message}")
  @logger.error(e.backtrace.join("\n"))
end

if __FILE__ == $PROGRAM_NAME
  main
end
