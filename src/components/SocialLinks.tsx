import React from 'react';
import LinkButton from './LinkButton';
import TwitterLinkGroup from './TwitterLinkGroup';

export default function SocialLinks() {
  return (
    <div className="space-y-4">
      <LinkButton href="https://twitch.tv/yuniruyuni" className="bg-purple-600 hover:bg-purple-700">
        Twitch Channel (Main streaming)
      </LinkButton>

      <LinkButton href="https://youtube.com/@yuniruyuni" className="bg-pink-500 hover:bg-pink-600">
        Youtube Channel
      </LinkButton>

      <TwitterLinkGroup />

      <LinkButton href="https://github.com/yuniruyuni" className="bg-slate-400 hover:bg-slate-500">
        Github
      </LinkButton>

      <LinkButton href="https://costume.yuniruyuni.net/" className="bg-green-400 hover:bg-green-500">
        お着替えリスト
      </LinkButton>

      <LinkButton href="https://hari-stream.com/ja/mypage/USER205ST1334/" className="border bg-pink-300 hover:bg-pink-200">
        HARI(おたより/質問箱)
      </LinkButton>
    </div>
  );
}
