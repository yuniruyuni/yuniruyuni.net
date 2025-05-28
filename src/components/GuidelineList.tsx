import React from 'react';

interface GuidelineListProps {
  children: React.ReactNode;
}

export default function GuidelineList({ children }: GuidelineListProps) {
  return (
    <ul className="md:w-full text-center md:text-left list-outside list-disc">
      {children}
    </ul>
  );
}