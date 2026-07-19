import Image from "next/image";
import { NotchDemo } from "./NotchDemo";

export function MacBook() {
  return (
    <div className="macWrap" aria-label="Notch Capture running from a MacBook notch">
      <div className="macDisplay">
        <div className="macBezel">
          <div className="macScreen">
            <div className="wallpaperGlow" />
            <div className="menuBar">
              <span>●</span><span>Finder</span><span>File</span><span>Edit</span><span>View</span>
              <span className="menuSpacer" /><span>⌁</span><span>10:41 AM</span>
            </div>
            <div className="hardwareNotch"><span /></div>
            <div className="desktopDemo"><NotchDemo /></div>
            <Image
              className="mobileHeroPoster"
              src="/media/implementation-expanded-v3.png"
              alt="Notch Capture expanded inbox"
              width={840}
              height={1120}
              priority
            />
          </div>
        </div>
      </div>
      <div className="macBase"><span /></div>
      <div className="macShadow" />
    </div>
  );
}
