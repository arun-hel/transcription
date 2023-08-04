#!/usr/bin/ruby
# encoding: UTF-8

require "optimist"
require "net/http"
require "jwt"
require "java_properties"
require "bbbevents"
require File.expand_path("../../../lib/recordandplayback", __FILE__)

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", "weekly")
logger.level = Logger::INFO
BigBlueButton.logger = logger

opts = Optimist::options do
  opt :meeting_id, "Meeting id to archive", :type => String
  opt :format, "Playback format name", :type => String
end
meeting_id = opts[:meeting_id]

bbb_web_properties = "/etc/bigbluebutton/bbb-web.properties"
events_xml = "/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml"
recording_path = "/var/bigbluebutton/published/presentation/#{meeting_id}"
transcript_file = "#{recording_path}/transcript.json"
webcams_file_path = "#{recording_path}/video"
video_format = "mp4"

def get_metadata(key, meeting_metadata)
  meeting_metadata.key?(key) ? meeting_metadata[key].value : nil
end

def get_callback_url(events_xml)
  meeting_metadata = BigBlueButton::Events.get_meeting_metadata(events_xml)
  meta_bbb_transcription_ready_url = "bbb-transcription-ready-url"
  callback_url = get_metadata(meta_bbb_transcription_ready_url, meeting_metadata)
  return callback_url
end

def is_transcription_enabled(events_xml)
  meeting_metadata = BigBlueButton::Events.get_meeting_metadata(events_xml)

  meta_bbb_transcription_enabled = "bbb-transcription-enabled"

  transcription_enabled = get_metadata(meta_bbb_transcription_enabled, meeting_metadata)
  return transcription_enabled == "true"
end

def http_client(uri, method, body = nil)
  uri = URI(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(
    uri,
    "content-type" => "application/json",
  )

  if !body.nil?
    request.body = body.to_json
  end

  response = http.request(request)
  return response
end

#
# Main code
#
BigBlueButton.logger.info("Transcription Ready Notify for [#{meeting_id}] starts")

is_event_xml_exist = File.exist?(events_xml)

if !is_event_xml_exist
  BigBlueButton.logger.info("Unable to find the events.xml file. Please check if the events.xml file exists at #{events_xml}")
  exit 0
end

events_data = BBBEvents.parse(events_xml)

begin
  callback_url = get_callback_url(events_xml)
  transcription_enabled = is_transcription_enabled(events_xml)
  BigBlueButton.logger.info("callback_url: #{callback_url} transcription_enabled: #{transcription_enabled}")
  unless callback_url.nil? || !transcription_enabled
    ffmped_cmd = "ffmpeg -y -i  #{webcams_file_path}/webcams.#{video_format} -vn -acodec pcm_s16le -ar 44100 -ac 2 #{webcams_file_path}/audio.wav"
    status = system(ffmped_cmd)
    BigBlueButton.logger.info("ffmpeg command status: #{status}")

    if status
      props = JavaProperties::Properties.new(bbb_web_properties)
      bbb_url = props["bigbluebutton.web.serverURL"].strip()
      audio_file = "#{webcams_file_path}/audio.wav"
      BigBlueButton.logger.info("Processing transcription for #{meeting_id}")

      response = `node /usr/local/bigbluebutton/core/scripts/post_publish/transcription_node_app/app.js #{audio_file} #{meeting_id}`
      transcription_data = JSON.parse(response)

      if transcription_data["status"] == "error"
        raise transcription_data["error"]
      end

      if transcription_data["status"] == "completed"
        BigBlueButton.logger.info("Transcription in completed for #{meeting_id}")
        is_transcription_done = true

        data_to_write = {
          "meeting_name" => events_data.metadata["meetingName"],
          "start_time" => events_data.start,
          "end_time" => events_data.finish,
          "meeting_id" => meeting_id,
          "transcription" => transcription_data["text"],
        }

        FileUtils.touch(transcript_file) if !File.file? (transcript_file)
        File.write(transcript_file, data_to_write.to_json)

        # Make a callback to the callback url only if the transcription file exists
        if File.file?(transcript_file)
          callback_data = {
            "meeting_name" => events_data.metadata["meetingName"],
            "start_time" => events_data.start,
            "end_time" => events_data.finish,
            "meeting_id" => meeting_id,
            "transcription_url" => "#{bbb_url}/presentation/#{meeting_id}/transcript.json",
          }
          response = http_client(callback_url, "post", callback_data)

          # check if the callback is successful using headers
          if response.code == "200"
            BigBlueButton.logger.info("Transcription ready callback successful for #{meeting_id}")
          else
            BigBlueButton.logger.info("Transcription ready callback failed for #{meeting_id} with status code #{response.code}")
          end
        end
      end
    end
  end
rescue Exception => e
  BigBlueButton.logger.info(e.to_s)
end
