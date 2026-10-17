(() => {
  const slides = [...document.querySelectorAll(".slide")];
  const currentNum = document.getElementById("currentNum");
  const progressBar = document.getElementById("progressBar");
  const notesBtn = document.getElementById("notesBtn");
  let index = 0;

  const show = (next) => {
    index = Math.max(0, Math.min(slides.length - 1, next));
    slides.forEach((slide, i) => {
      slide.classList.toggle("is-active", i === index);
    });
    currentNum.textContent = String(index + 1);
    progressBar.style.width = `${((index + 1) / slides.length) * 100}%`;
    history.replaceState(null, "", `#${index + 1}`);
  };

  const fromHash = () => {
    const n = Number(location.hash.replace("#", ""));
    if (Number.isFinite(n) && n >= 1 && n <= slides.length) show(n - 1);
    else show(0);
  };

  document.getElementById("prevBtn").addEventListener("click", () => show(index - 1));
  document.getElementById("nextBtn").addEventListener("click", () => show(index + 1));

  notesBtn.addEventListener("click", () => {
    const on = document.body.classList.toggle("show-notes");
    notesBtn.setAttribute("aria-pressed", String(on));
  });

  document.getElementById("fsBtn").addEventListener("click", () => {
    if (!document.fullscreenElement) document.documentElement.requestFullscreen?.();
    else document.exitFullscreen?.();
  });

  window.addEventListener("keydown", (e) => {
    if (e.target.matches("input, textarea")) return;
    if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") {
      e.preventDefault();
      show(index + 1);
    }
    if (e.key === "ArrowLeft" || e.key === "PageUp") {
      e.preventDefault();
      show(index - 1);
    }
    if (e.key === "n" || e.key === "N" || e.key === "н" || e.key === "Н") {
      notesBtn.click();
    }
    if (e.key === "f" || e.key === "F" || e.key === "а" || e.key === "А") {
      document.getElementById("fsBtn").click();
    }
    if (e.key === "Home") show(0);
    if (e.key === "End") show(slides.length - 1);
  });

  window.addEventListener("hashchange", fromHash);
  fromHash();
})();
