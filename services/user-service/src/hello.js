function sayHi() {
  console.log("Hi from ShopEasy CronJob! Time is: " + new Date().toISOString());
  process.exit(0);
}

sayHi();
