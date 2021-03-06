module PkgAdapter

  class Ipa < BaseAdapter
    
    require 'zip'

    def parse
        Zip::File.open(@path) do |zip_file|
          # Handle entries one by one
          path = tmp_dir
          FileUtils.rm_rf path
          # zip_file.each do |entry|
          #   # Extract to file/directory/symlink
          #   p "Extracting #{entry.name}"
          #   entry.extract("#{path}/#{entry.name}")
          #   # content = entry.get_input_stream.read if entry.get_input_stream.respond_to? :read
          # end

          provision = zip_file.glob("Payload/*.app/embedded.mobileprovision").first
          @provision = provision ? ConfigParser.mobileprovision(provision.get_input_stream.read) : {}
          
          plist = zip_file.glob("Payload/*.app/Info.plist").first
          @plist = plist ? ConfigParser.plist(plist.get_input_stream.read) : {}
          
          # read supported devices from UIDeviceFamily(https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html#//apple_ref/doc/uid/TP40009252-SW11)
          supportDevices = @plist["UIDeviceFamily"]
          
          # read icon name
          appIconName = "AppIcon"
          
          @supportDevicesDesc = ""
          if supportDevices.count > 0
              if supportDevices.count == 2
                  # 通用安装包
                  @supportDevicesDesc = "iPhone(iPod)/iPad"
                  appIconName = @plist["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"]
                  elsif supportDevices[0] == 1
                  #iPhone设备
                  @supportDevicesDesc = "iPhone(iPod)"
                  appIconName = @plist["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"]
                  else
                  #iPad设备
                  @supportDevicesDesc = "iPad"
                  appIconName = @plist["CFBundleIcons~ipad"]["CFBundlePrimaryIcon"]["CFBundleIconName"]
              end
          end
          
          entry = zip_file.glob("Payload/*.app/#{appIconName}[6,4]0x[6,4]0@*.png").last
          
          if entry
            @app_icon = "#{path}/#{entry.name}"
            dirname = File.dirname(@app_icon)
            FileUtils.mkdir_p dirname

            entry.extract @app_icon
            
            #uncrush
            png = PNG.normalize(@app_icon)
            File.open("#{@app_icon}", 'wb') { |file| file.write(png) } if png
          else
            p "can find AppIcon"
          end
        end
    end

    def plat
      'ios'
    end

    def app_uniq_key
      :build
    end

    def app_name
      @plist["CFBundleDisplayName"] || @plist["CFBundleName"]
    end

    def app_version
      @plist["CFBundleShortVersionString"]
    end

    def app_build
      @plist["CFBundleVersion"]
    end

    def app_icon
      @app_icon
    end

    def app_size
      File.size(@path)
    end

    def app_bundle_id
      @plist["CFBundleIdentifier"]
    end

    def app_supportDevices
        @supportDevicesDesc
    end

    def ext_info
      if @provision.present?
        devices = @provision["ProvisionedDevices"];
        info = {
          "包类型" => devices ? "Ad-hoc" : "Release",
          "包信息" => [
            "支持安装设备: #{self.app_supportDevices}",
            "包名: #{self.app_bundle_id}",
            "体积: #{app_size_mb}MB",
            "MD5: #{pkg_mb5}"
          ],
          "描述文件" => [
            "名称: #{@provision['Name']}",
            "TeamName: #{@provision['TeamName']}",
            "TeamID: #{@provision['TeamIdentifier']&.join(',')}",
            "创建时间: #{@provision['CreationDate']}",
            "过期时间: #{@provision['ExpirationDate']}",
            "UUID: #{@provision['UUID']}",
          ],
          "Entitlements" => @provision['Entitlements']&.map{|k,v| "#{k}: #{v}" },
        }
      else
        info = {
          "包类型" => "未知",
          "包信息" => [
            "包名: #{self.app_bundle_id}",
            "体积: #{app_size_mb}MB",
            "MD5: #{pkg_mb5}"
          ]
        }
      end
      if devices
        info["包含设备 (#{devices.count}台)"] = devices
      end
      info
    end

  end

  class ConfigParser

    def self.mobileconfig(stream)
      #稳定后迁移
      plist_begin = stream.index('<?xml version=')
      plist_end = stream.index('</plist>') + 8
      profile = stream[plist_begin...plist_end]
      CFPropertyList::List.new(:data => profile).value
    end

    def self.mobileprovision(stream)
      # security cms -D -i Reutte.app/embedded.mobileprovision
      profile = stream.slice(stream.index('<?'), stream.length)
      self.plist(Nokogiri.XML(profile).to_xml)
    end

    def self.plist(stream)
      if stream[0..5] == "bplist"
        Bplist.parse(stream).tree
      else
        Plist.parse_xml(stream)
      end
    end
  end
end
