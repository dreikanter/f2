# frozen_string_literal: true

# Reports EU stock for the VPS 2027 range from OVH's public order-rule API.
#
# Usage:
#   ruby script/ovh_vps_stock.rb
#
# Everything is configured by the constants below — edit SUBSIDIARY to look at a
# different OVH entity. Note that a subsidiary only ever sees the datacenters it
# sells: the US DCs (us-east-vin, us-west-hil) never appear for an EU
# subsidiary, they live behind ovhSubsidiary=US on the api.us.ovhcloud.com host.
#
# On the two status columns: `status` is availability for any OS, `linux` is
# Linux specifically. They disagree often (Limburg and Milan are routinely
# "available" while Linux is out of stock), and `linux` is the one that matches
# what the web configurator offers, since it defaults to Linux. Read the linux
# column unless you're ordering Windows.

require "json"
require "net/http"

SUBSIDIARY = "IE"
API_HOST = "https://eu.api.ovh.com/1.0"

# LZ is a separate SKU with its own city-level zones and reduced features
# (Linux only, no additional IPs, no load balancer) — never merge it into VPS-2.
PLANS = {
  "vps-2027-model1" => "VPS-1",
  "vps-2027-model2" => "VPS-2",
  "vps-2027-model3" => "VPS-3",
  "vps-2027-model4" => "VPS-4",
  "vps-2027-model2.LZ" => "VPS-2 LZ"
}.freeze

COUNTRIES = {
  "eu-west-eri" => "UK (Erith)",
  "eu-west-gra" => "France (Gravelines)",
  "eu-west-rbx" => "France (Roubaix)",
  "eu-west-sbg" => "France (Strasbourg)",
  "eu-west-lim" => "Germany (Limburg)",
  "eu-central-waw" => "Poland (Warsaw)",
  "eu-south-mil" => "Italy (Milan)"
}.freeze

LZ_CITIES = {
  "ams" => "Netherlands (Amsterdam)",
  "bru" => "Belgium (Brussels)",
  "mad" => "Spain (Madrid)",
  "mrs" => "France (Marseille)",
  "prg" => "Czechia (Prague)",
  "vie" => "Austria (Vienna)",
  "zrh" => "Switzerland (Zurich)"
}.freeze

def location(code)
  return COUNTRIES[code] if COUNTRIES.key?(code)
  return LZ_CITIES.fetch(code.split("-").last, code) if code.include?("-lz-")

  code
end

def datacenters(plan_code)
  uri = URI("#{API_HOST}/vps/order/rule/datacenter")
  uri.query = URI.encode_www_form(ovhSubsidiary: SUBSIDIARY, planCode: plan_code)
  response = Net::HTTP.get_response(uri)
  raise "#{plan_code}: HTTP #{response.code} — #{response.body}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body).fetch("datacenters").select { |dc| dc["code"].start_with?("eu-") }
end

puts "OVH VPS 2027 — EU availability (subsidiary: #{SUBSIDIARY})"

PLANS.each do |plan_code, name|
  rows = datacenters(plan_code).sort_by { |dc| [dc["linuxStatus"] == "available" ? 0 : 1, location(dc["code"])] }

  puts
  puts "#{name} (#{plan_code})"
  if rows.empty?
    puts "  no EU datacenters offered"
    next
  end

  rows.each do |dc|
    mark = dc["linuxStatus"] == "available" ? "*" : " "
    puts format("  %s %-24s %-17s status: %-12s linux: %s",
                mark, location(dc["code"]), dc["code"], dc["status"], dc["linuxStatus"])
  end
end
