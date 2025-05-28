import React from 'react';

interface LinkButtonProps {
  href: string;
  children: React.ReactNode;
  className?: string;
}

export default function LinkButton({ href, children, className = '' }: LinkButtonProps) {
  const baseClasses = "block w-full md:w-auto text-white font-bold py-2 px-4 rounded-full transition duration-300 ease-in-out";
  
  return (
    <a href={href} className={`${baseClasses} ${className}`}>
      {children}
    </a>
  );
}