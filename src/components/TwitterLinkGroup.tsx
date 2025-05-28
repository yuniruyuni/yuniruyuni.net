import React from 'react';
import LinkGroup from './LinkGroup';

export default function TwitterLinkGroup() {
  const links = [
    {
      href: "https://twitter.com/yuniruyuni",
      text: "Twitter(X)"
    },
    {
      href: "https://twitter.com/hashtag/yunicode", 
      label: "Tag",
      text: "#yunicode"
    },
    {
      href: "https://twitter.com/hashtag/yunigraphics",
      label: "FanArt", 
      text: "#yunigraphics"
    }
  ];

  return <LinkGroup links={links} />;
}