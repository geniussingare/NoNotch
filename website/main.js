// Hero island: cycles through states like the real app; hovering expands it.
(() => {
  const island = document.getElementById("island");
  if (!island) return;

  const sequence = [
    ["idle", 1400],
    ["music", 2200],
    ["expanded", 3400],
    ["music", 1400],
    ["banner", 3000],
    ["music", 1200],
    ["hud", 1800],
    ["charge", 2200],
  ];
  let step = 0;
  let timer;
  let hovering = false;
  const meter = island.querySelector(".compact-hud .meter i");

  const set = (state) => {
    island.dataset.state = state;
    if (state === "hud" && meter) {
      meter.style.width = "40%";
      setTimeout(() => (meter.style.width = "75%"), 450);
      setTimeout(() => (meter.style.width = "60%"), 1000);
    }
  };

  const advance = () => {
    if (hovering) return;
    const [state, duration] = sequence[step % sequence.length];
    set(state);
    step += 1;
    timer = setTimeout(advance, duration);
  };

  island.addEventListener("mouseenter", () => {
    hovering = true;
    clearTimeout(timer);
    set("expanded");
  });
  island.addEventListener("mouseleave", () => {
    hovering = false;
    set("music");
    timer = setTimeout(advance, 900);
  });
  island.addEventListener("click", () => set(island.dataset.state === "expanded" ? "music" : "expanded"));

  advance();
})();

// Pull-cord demo: drag down to drop the island, it springs back after.
(() => {
  const demo = document.getElementById("cord");
  if (!demo) return;
  const cord = demo.querySelector(".cord");
  const string = cord.querySelector(".string");

  const island = document.createElement("div");
  island.className = "island";
  island.dataset.state = "idle";
  island.style.setProperty("--w", "0px");
  island.style.setProperty("--h", "0px");
  demo.appendChild(island);

  let startY = null;
  let swayed = false;

  const sway = () => {
    cord.animate(
      [
        { transform: "translateX(-50%) rotate(0deg)" },
        { transform: "translateX(-50%) rotate(8deg)" },
        { transform: "translateX(-50%) rotate(-6deg)" },
        { transform: "translateX(-50%) rotate(3deg)" },
        { transform: "translateX(-50%) rotate(0deg)" },
      ],
      { duration: 1100, easing: "ease-out" }
    );
  };
  cord.style.transform = "translateX(-50%)";

  demo.addEventListener("mousemove", (event) => {
    const rect = cord.getBoundingClientRect();
    const near = Math.abs(event.clientX - (rect.left + rect.width / 2)) < 60 && event.clientY - rect.top < 90;
    if (near && !swayed) {
      swayed = true;
      sway();
    } else if (!near) {
      swayed = false;
    }
  });

  const open = () => {
    cord.style.opacity = "0";
    island.style.setProperty("--w", "300px");
    island.style.setProperty("--h", "120px");
    island.style.setProperty("--r", "0 0 30px 30px");
    setTimeout(() => {
      island.style.setProperty("--w", "0px");
      island.style.setProperty("--h", "0px");
      setTimeout(() => (cord.style.opacity = "1"), 350);
    }, 2200);
  };

  cord.addEventListener("pointerdown", (event) => {
    startY = event.clientY;
    cord.setPointerCapture(event.pointerId);
  });
  cord.addEventListener("pointermove", (event) => {
    if (startY === null) return;
    const pull = Math.max(0, Math.min((event.clientY - startY) * 0.7, 40));
    string.style.height = `${14 + pull}px`;
  });
  cord.addEventListener("pointerup", (event) => {
    if (startY === null) return;
    const pulled = event.clientY - startY > 16 || Math.abs(event.clientY - startY) < 3;
    startY = null;
    string.animate([{ height: string.style.height }, { height: "14px" }], {
      duration: 500,
      easing: getComputedStyle(document.documentElement).getPropertyValue("--spring").trim() || "ease-out",
    });
    string.style.height = "14px";
    if (pulled) open();
  });
})();

// Reveal sections as they scroll into view.
(() => {
  const targets = document.querySelectorAll(".card, .pillars div, .section h2, .split > div, .download img");
  targets.forEach((el) => el.classList.add("reveal"));
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15 }
  );
  targets.forEach((el, i) => {
    el.style.transitionDelay = `${(i % 3) * 70}ms`;
    observer.observe(el);
  });
})();

// Pause looping demo animations while they're off screen.
(() => {
  const loops = document.querySelectorAll(".mac, .feature-media, .feature-motion");
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => entry.target.classList.toggle("paused", !entry.isIntersecting));
  });
  loops.forEach((el) => observer.observe(el));
})();
