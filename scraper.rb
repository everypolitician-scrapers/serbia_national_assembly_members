# frozen_string_literal: true
# #!/bin/env ruby
# encoding: utf-8

require 'pry'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

class MembersPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :member_urls do
    noko.css('div.delegate_list tr td a/@href').map(&:text)
  end
end

class MemberPage < Scraped::HTML
  field :id do
    url.to_s.gsub(/^.*\.(\d+)\.\d+.*$/, '\1')
  end

  field :dob do
    details.xpath('//h4[contains(.,"Year of Birth")]/following-sibling::p[not(position() > 1)]/text()').to_s.delete('.').tidy
  end

  field :start_date do
    start = details.xpath('//h4[contains(.,"Date of Verification of")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
    Date.parse(start).to_s
  end

  private

  def details
    noko.css('div.optimize')
  end
end

def scraper(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def get_social_details(social)
  details = {}
  social.each do |item|
    details[:facebook] = item.css('a/@href').to_s if item.text.to_s.index('Facebook account')
    details[:twitter] = item.css('a/@href').to_s if item.text.to_s.index('Twitter account')
    details[:website] = item.css('a/@href').to_s if item.text.to_s.index('Personal website')
  end

  details
end

def fix_name(name)
  # we can't re-order the name parts because they don't seem to be
  # consistent on all the pages so lets not try. We can extract
  # Dr etc thoough so do that
  honorific_prefix = ''
  name.gsub(/(\s+(?:(?:Prof|Dr|Mrs|Dr\.med\.dent)\.?\s+)+)/i) do
    honorific_prefix = Regexp.last_match(1) or ''
    if honorific_prefix.size
      name = name.gsub(honorific_prefix, ' ')
      honorific_prefix = honorific_prefix.gsub('. ', ' ').tidy
      honorific_prefix = honorific_prefix.gsub('.$', '').tidy
      honorific_prefix = honorific_prefix.split(' ').map(&:capitalize) .join(' ')
    end
  end

  honorific_suffix = ''
  name.gsub(/(\s+(?:(?:PhD|MD|Prim|M\.?Sci)\.?\s+)+)/i) do
    honorific_suffix = Regexp.last_match(1) or ''
    if honorific_suffix.size
      name = name.gsub(honorific_suffix, ' ')
      honorific_suffix = honorific_suffix.gsub('. ', ' ').tidy
      honorific_suffix = honorific_suffix.gsub('.$', '').tidy
    end
  end

  name = name.gsub(' - ', ' ').tidy

  [name, honorific_prefix, honorific_suffix]
end

def scrape_list(url)
  scraper(url => MembersPage).member_urls.each do |url|
    scrape_person(url)
  end
end

def scrape_person(url)
  # We're going to migrate to Scraped field-by-field, so we need both for now
  noko = noko_for(url)
  page = scraper(url => MemberPage)

  details = noko.css('div.optimize')

  name = details.css('h2').text.to_s.tidy
  sort_name = name

  name, honorific_prefix, honorific_suffix = fix_name(name)

  party = details.xpath('//h4[contains(.,"Political party")]/following-sibling::p[not(position() > 1)]/text()').to_s
  party = party.gsub(/\(.*$/, '').tidy
  party = '' if party == '-'

  faction = details.xpath('//h4[contains(.,"Parliamentary group")]/following-sibling::p[position() = 1]/a[not(position() > 1)]/text()').to_s
  faction = faction.gsub('Read more ˃˃', '')
  faction = faction.gsub('Parliamentary Group', '').tidy
  faction = '' if faction == 'MPs not members of parliamentary groups'

  social = noko.xpath('//div[contains(@class,"single_member")]/following-sibling::div/ul/li')
  social_details = get_social_details(social)

  data = {
    id:               page.id,
    name:             name,
    sort_name:        sort_name,
    honorific_prefix: honorific_prefix,
    honorific_suffix: honorific_suffix,
    faction:          faction,
    party:            party,
    start_date:       page.start_date,
    birth_date:       page.dob,
    term:             6,
    source:           url.to_s,
  }

  data = data.merge(social_details)
  # puts data.reject { |k,v| v.to_s.empty? }.sort_by { |k,v| k }.to_h

  ScraperWiki.save_sqlite(%i(id term), data)
end

scrape_list('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html')
