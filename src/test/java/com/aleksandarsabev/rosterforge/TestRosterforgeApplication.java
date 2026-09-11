package com.aleksandarsabev.rosterforge;

import org.springframework.boot.SpringApplication;

public class TestRosterforgeApplication {

    public static void main(String[] args) {
        SpringApplication.from(RosterforgeApplication::main).with(TestcontainersConfiguration.class).run(args);
    }

}
