function privbus(pob) {
  if (pob == "private") {
    document.getElementById('data_business').style.display = 'none';
    document.getElementById('contact_business').style.display = 'none';
  } else {
    document.getElementById('data_business').style.display = 'block';
    document.getElementById('contact_business').style.display = 'block';
  }
}
