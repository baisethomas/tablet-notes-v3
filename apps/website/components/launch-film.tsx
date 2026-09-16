"use client";

import { useRef } from "react";
import { Play, X } from "lucide-react";

export function LaunchFilm() {
  const dialog = useRef<HTMLDialogElement>(null);
  const video = useRef<HTMLVideoElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);

  function closeFilm() {
    dialog.current?.close();
  }
  function onClose() {
    video.current?.pause();
    trigger.current?.focus();
  }

  return (
    <>
      <button
        className="film-button"
        ref={trigger}
        onClick={() => dialog.current?.showModal()}
      >
        <Play size={17} aria-hidden="true" fill="currentColor" /> Watch the
        launch film <span>0:05</span>
      </button>
      <dialog
        ref={dialog}
        className="film-dialog"
        aria-labelledby="film-dialog-title"
        onClose={onClose}
        onClick={(event) => {
          if (event.target === event.currentTarget) closeFilm();
        }}
      >
        <div className="film-dialog-header">
          <h2 id="film-dialog-title">Tablet Notes is live.</h2>
          <button onClick={closeFilm} aria-label="Close launch film" autoFocus>
            <X />
          </button>
        </div>
        <video
          ref={video}
          controls
          playsInline
          preload="none"
          poster="/launch/film-poster.jpg"
          aria-label="Five-second Tablet Notes launch film: a phone and pen-nib logo surrounded by moving paper and golden light, ending with Now on the App Store."
        >
          <source src="/launch/film.webm" type="video/webm" />
          <source src="/launch/film.mp4" type="video/mp4" />
          Your browser does not support video playback.
        </video>
        <p>Tablet Notes. Now on the App Store.</p>
      </dialog>
    </>
  );
}
