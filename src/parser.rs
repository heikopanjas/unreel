//! RSS/XML feed parsing functionality

use quick_xml::{Reader, events::Event};

use crate::Result;

/// Represents a parsed podcast feed
#[derive(Debug)]
pub struct PodcastFeed
{
    pub title:       Option<String>,
    pub description: Option<String>,
    pub link:        Option<String>,
    pub items:       Vec<PodcastItem>
}

/// Represents a single podcast episode
#[derive(Debug)]
pub struct PodcastItem
{
    pub title:       Option<String>,
    pub description: Option<String>,
    pub enclosure:   Option<Enclosure>,
    pub pub_date:    Option<String>,
    pub guid:        Option<String>
}

/// Represents a podcast episode's audio file
#[derive(Debug)]
pub struct Enclosure
{
    pub url:    String,
    pub length: Option<String>,
    pub mime:   Option<String>
}

/// Parses an RSS/XML podcast feed
///
/// Extracts feed metadata and episode information from the XML content.
///
/// # Arguments
///
/// * `xml_content` - The raw XML content of the podcast feed
///
/// # Returns
///
/// Returns a parsed `PodcastFeed` structure
///
/// # Errors
///
/// Returns an error if the XML is malformed or cannot be parsed
pub fn parse_feed(xml_content: &str) -> Result<PodcastFeed>
{
    let mut reader = Reader::from_str(xml_content);
    reader.config_mut().trim_text(true);

    let mut feed = PodcastFeed { title: None, description: None, link: None, items: Vec::new() };

    let mut current_item: Option<PodcastItem> = None;
    let mut current_tag = String::new();
    let mut buf = Vec::new();

    loop
    {
        match reader.read_event_into(&mut buf)
        {
            | Ok(Event::Start(ref e)) =>
            {
                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                current_tag = tag_name.clone();

                if tag_name == "item"
                {
                    current_item = Some(PodcastItem { title: None, description: None, enclosure: None, pub_date: None, guid: None });
                }
                else if tag_name == "enclosure" &&
                    let Some(ref mut item) = current_item
                {
                    let mut url = None;
                    let mut length = None;
                    let mut mime = None;

                    for attr in e.attributes().filter_map(|a| a.ok())
                    {
                        let key = String::from_utf8_lossy(attr.key.as_ref()).to_string();
                        let value = String::from_utf8_lossy(&attr.value).to_string();

                        match key.as_str()
                        {
                            | "url" => url = Some(value),
                            | "length" => length = Some(value),
                            | "type" => mime = Some(value),
                            | _ =>
                            {}
                        }
                    }

                    if let Some(url_value) = url
                    {
                        item.enclosure = Some(Enclosure { url: url_value, length, mime });
                    }
                }
            }
            | Ok(Event::Text(e)) =>
            {
                let text = reader.decoder().decode(&e)?.to_string();

                if current_item.is_some() == true
                {
                    if let Some(ref mut item) = current_item
                    {
                        match current_tag.as_str()
                        {
                            | "title" => item.title = Some(text),
                            | "description" => item.description = Some(text),
                            | "pubDate" => item.pub_date = Some(text),
                            | "guid" => item.guid = Some(text),
                            | _ =>
                            {}
                        }
                    }
                }
                else
                {
                    match current_tag.as_str()
                    {
                        | "title" => feed.title = Some(text),
                        | "description" => feed.description = Some(text),
                        | "link" => feed.link = Some(text),
                        | _ =>
                        {}
                    }
                }
            }
            | Ok(Event::End(ref e)) =>
            {
                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                if tag_name == "item" &&
                    let Some(item) = current_item.take()
                {
                    feed.items.push(item);
                }
            }
            | Ok(Event::Eof) => break,
            | Err(e) => return Err(format!("Error parsing XML at position {}: {}", reader.buffer_position(), e).into()),
            | _ =>
            {}
        }

        buf.clear();
    }

    Ok(feed)
}
