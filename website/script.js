// BizLinq marketing site — mobile menu, FAQ accordion, footer year.
(function () {
  // Close the mobile menu when a link is tapped.
  document.querySelectorAll(".mobile-menu a").forEach(function (link) {
    link.addEventListener("click", function () {
      document.querySelector(".mobile-menu").classList.remove("open");
    });
  });

  // FAQ accordion: one open at a time.
  document.querySelectorAll(".faq-item").forEach(function (item) {
    var button = item.querySelector(".faq-q");
    var answer = item.querySelector(".faq-a");
    if (!button || !answer) return;
    button.addEventListener("click", function () {
      var isOpen = item.classList.contains("open");
      document.querySelectorAll(".faq-item.open").forEach(function (other) {
        other.classList.remove("open");
        other.querySelector(".faq-a").style.maxHeight = "0px";
      });
      if (!isOpen) {
        item.classList.add("open");
        answer.style.maxHeight = answer.scrollHeight + "px";
      }
    });
  });
})();
