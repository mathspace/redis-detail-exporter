package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"

	"github.com/redis/go-redis/v9"
)

var (
	redisAddr = os.Getenv("REDIS_ADDR")
)

func getDBs() ([]int, error) {
	ctx := context.Background()
	client := redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})
	defer client.Close()

	// Get DB with keys using info command

	lines, err := client.Info(ctx, "keyspace").Result()
	if err != nil {
		return nil, err
	}
	pat := regexp.MustCompile(`(?m)^db(\d+):`)
	m := pat.FindAllStringSubmatch(lines, -1)
	dbs := make([]int, len(m))
	for i, v := range m {
		n, _ := strconv.Atoi(v[1])
		dbs[i] = n
	}
	return dbs, nil
}

func getQueueLengths(db int) (map[string]int64, error) {
	qLens := make(map[string]int64)
	ctx := context.Background()
	client := redis.NewClient(&redis.Options{
		Addr: redisAddr,
		DB:   db,
	})
	defer client.Close()

	// Get keys
	keys, err := client.Keys(ctx, "*").Result()
	if err != nil {
		return nil, err
	}
	for _, key := range keys {
		// Get length of list
		l, err := client.LLen(ctx, key).Result()
		if err == nil {
			// Non-list keys will throw errors, so ignore.
			qLens[key] = l
		}
	}
	return qLens, nil
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "# HELP redis_queue_length Length of Redis queue")
	fmt.Fprintln(w, "# TYPE redis_queue_length gauge")

	dbs, err := getDBs()
	if err != nil {
		log.Printf("Error getting DBs: %v", err)
		return
	}
	for _, db := range dbs {
		qLens, err := getQueueLengths(db)
		if err != nil {
			log.Printf("Error getting queue lengths: %v", err)
			continue
		}
		for k, v := range qLens {
			fmt.Fprintf(w, "redis_queue_length{db=\"%d\",queue=\"%s\"} %d\n", db, k, v)
		}
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8001"
	}
	http.HandleFunc("/metrics", handleMetrics)
	http.ListenAndServe(":"+port, nil)
}
